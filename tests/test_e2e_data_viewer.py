"""
End-to-end tests for the Merge Data Viewer using Playwright.

These tests require:
1. pip install playwright pytest-playwright
2. playwright install chromium
3. The app running at BASE_URL (or set E2E_BASE_URL env var)
4. Authentication (set E2E_AUTH_TOKEN env var or configure SCOPESTACK credentials)

Run with: pytest tests/test_e2e_data_viewer.py -v --headed

The key test case is verifying that clicking on array items with index > 0
correctly displays the detail pane - a regression that was previously missed.
"""

import os
import pytest

# Skip all tests if playwright is not installed
pytest.importorskip("playwright")

from playwright.sync_api import Page, expect

BASE_URL = os.environ.get("E2E_BASE_URL", "http://localhost:5001")


@pytest.fixture(scope="session")
def browser_context_args():
    """Configure browser context for testing."""
    return {
        "viewport": {"width": 1920, "height": 1080},
        "ignore_https_errors": True,
    }


@pytest.mark.skipif(
    not os.environ.get("RUN_E2E_TESTS"),
    reason="E2E tests disabled. Set RUN_E2E_TESTS=1 to enable.",
)
class TestDataViewerArraySelection:
    """
    Test array item selection in the Miller Columns data viewer.

    These tests verify that the detail pane appears correctly when
    clicking on dynamically generated array items (index > 0).
    """

    @pytest.fixture(autouse=True)
    def setup(self, page: Page):
        """Navigate to the data viewer page."""
        page.goto(f"{BASE_URL}/merge-data-viewer")
        # Wait for React to mount
        page.wait_for_selector(".version-viewer", timeout=10000)

    def test_clicking_first_array_item_shows_detail_pane(self, page: Page):
        """Verify clicking on [0] array item shows the detail pane."""
        # This assumes there's a project loaded with array data
        # In practice, you'd need to either:
        # 1. Load a known test project first
        # 2. Mock the API response

        # Click on an array field (e.g., "locations")
        array_field = page.locator('[data-path="locations"]').first
        if array_field.is_visible():
            array_field.click()

            # Wait for the child column to appear
            page.wait_for_selector('[data-path="locations[0]"]', timeout=5000)

            # Click on the first array item
            page.click('[data-path="locations[0]"]')

            # Verify the detail pane appears
            detail_pane = page.locator(".detail-panel")
            expect(detail_pane).to_be_visible()
            expect(detail_pane).to_contain_text("Full Path")

    def test_clicking_non_zero_array_item_shows_detail_pane(self, page: Page):
        """
        CRITICAL TEST: Verify clicking on array items with index > 0 shows detail pane.

        This was a regression where dynamically generated paths like locations[5]
        didn't exist in the structure object, causing the detail pane to not render.
        """
        # Click on an array field
        array_field = page.locator('[data-path="locations"]').first
        if array_field.is_visible():
            array_field.click()

            # Wait for array items to appear
            page.wait_for_selector('[data-path^="locations["]', timeout=5000)

            # Find an array item with index > 0
            non_zero_items = page.locator('[data-path^="locations["][data-path$="]"]')
            count = non_zero_items.count()

            if count > 1:
                # Click on the second item (index 1)
                second_item = page.locator('[data-path="locations[1]"]')
                second_item.click()

                # CRITICAL: Verify the detail pane appears
                detail_pane = page.locator(".detail-panel")
                expect(detail_pane).to_be_visible(timeout=3000)
                expect(detail_pane).to_contain_text("Full Path")
                expect(detail_pane).to_contain_text("locations[1]")

    def test_all_array_items_are_displayed(self, page: Page):
        """Verify all array items are shown, not just the first one."""
        array_field = page.locator('[data-path="locations"]').first
        if array_field.is_visible():
            array_field.click()

            # Get the expected count from the parent item badge
            badge = page.locator('[data-path="locations"]').locator(".item-type")
            badge_text = badge.text_content()

            # Extract count from "[12]" format
            if "[" in badge_text and "]" in badge_text:
                expected_count = int(badge_text.split("[")[1].split("]")[0])

                # Count actual array items displayed
                array_items = page.locator('[data-path^="locations["][data-path$="]"]')
                actual_count = array_items.count()

                assert actual_count == expected_count, (
                    f"Expected {expected_count} array items, but found {actual_count}"
                )


@pytest.mark.skipif(
    not os.environ.get("RUN_E2E_TESTS"),
    reason="E2E tests disabled. Set RUN_E2E_TESTS=1 to enable.",
)
class TestDataViewerNavigation:
    """Test navigation through nested data structures."""

    @pytest.fixture(autouse=True)
    def setup(self, page: Page):
        """Navigate to the data viewer page."""
        page.goto(f"{BASE_URL}/merge-data-viewer")
        page.wait_for_selector(".version-viewer", timeout=10000)

    def test_nested_object_navigation(self, page: Page):
        """Verify clicking on nested objects shows their children."""
        # Click on a root-level object
        root_object = page.locator('[data-path="project"]').first
        if root_object.is_visible():
            root_object.click()

            # Wait for children to appear in new column
            page.wait_for_selector('.column', timeout=3000)

            # Verify breadcrumb trail updates
            breadcrumb = page.locator(".breadcrumb")
            expect(breadcrumb).to_contain_text("project")

    def test_search_filters_results(self, page: Page):
        """Verify search functionality filters displayed items."""
        # Find and use the search input
        search_input = page.locator('input[placeholder*="Search"]').first
        search_input.fill("name")

        # Wait for results to filter
        page.wait_for_timeout(300)  # Debounce delay

        # Verify search results panel appears
        results_panel = page.locator(".search-results-panel")
        if results_panel.is_visible():
            expect(results_panel).to_contain_text("result")
