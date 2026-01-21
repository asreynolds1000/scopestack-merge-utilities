"""
Pytest fixtures for ScopeStack Template Converter tests.
"""

import pytest
import tempfile
import zipfile
import os


@pytest.fixture
def sample_xml_with_merge_fields():
    """Sample Word document XML containing mail merge fields."""
    # Note: Word adds trailing backslash and asterisk after field names
    return '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:fldChar w:fldCharType="begin"/>
      </w:r>
      <w:r>
        <w:instrText>MERGEFIELD =client_name \\* MERGEFORMAT</w:instrText>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="separate"/>
      </w:r>
      <w:r>
        <w:t>«client_name»</w:t>
      </w:r>
      <w:r>
        <w:fldChar w:fldCharType="end"/>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:instrText>MERGEFIELD =project_name \\* MERGEFORMAT</w:instrText>
      </w:r>
    </w:p>
  </w:body>
</w:document>'''


@pytest.fixture
def sample_xml_with_loops():
    """Sample XML containing Sablon loop structures."""
    return '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:instrText>MERGEFIELD locations:each(location)</w:instrText>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:instrText>MERGEFIELD =location.name</w:instrText>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:instrText>MERGEFIELD locations:endEach</w:instrText>
      </w:r>
    </w:p>
  </w:body>
</w:document>'''


@pytest.fixture
def sample_xml_with_conditionals():
    """Sample XML containing Sablon conditional structures."""
    return '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r>
        <w:instrText>MERGEFIELD locations:if(any?)</w:instrText>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:t>Content when locations exist</w:t>
      </w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:instrText>MERGEFIELD locations:endIf</w:instrText>
      </w:r>
    </w:p>
  </w:body>
</w:document>'''


@pytest.fixture
def temp_docx(tmp_path):
    """Create a temporary .docx file with test content."""
    def _create_docx(document_xml_content):
        docx_path = tmp_path / "test_template.docx"

        # Create minimal docx structure
        with zipfile.ZipFile(docx_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            # [Content_Types].xml
            content_types = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>'''
            zf.writestr('[Content_Types].xml', content_types)

            # _rels/.rels
            rels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''
            zf.writestr('_rels/.rels', rels)

            # word/_rels/document.xml.rels
            doc_rels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>'''
            zf.writestr('word/_rels/document.xml.rels', doc_rels)

            # word/document.xml
            zf.writestr('word/document.xml', document_xml_content)

        return str(docx_path)

    return _create_docx


@pytest.fixture
def temp_output_path(tmp_path):
    """Provide a temporary output path for converted documents."""
    return str(tmp_path / "output.docx")
