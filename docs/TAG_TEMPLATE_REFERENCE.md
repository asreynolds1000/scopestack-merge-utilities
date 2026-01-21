# Tag Template Reference - Based on ScopeStack Documentation

This reference is compiled from ScopeStack's official help articles to ensure accurate conversion.

## Key Concepts

### Tag Templates vs Mail Merge Templates

**Tag Templates:**
- Use industry-standard rendering engine
- Require V2 merge data in JSON format
- Use `{field}` syntax
- Support advanced features like filters and comparisons

**Mail Merge Templates (Legacy):**
- Use Microsoft Word Mail Merge fields
- Support built-in formatting wrappers (`.to_currency`, `.to_short_date`)
- Being replaced by Tag Templates

## Tag Syntax Reference

### Basic Tags

| Purpose | Syntax | Example |
|---------|--------|---------|
| Text field | `{field}` | `{project.client_name}` |
| Conditional | `{#field}...{/field}` | `{#project.msa_date}...{/project.msa_date}` |
| Inverted conditional | `{^field}...{/field}` | `{^project.msa_date}...{/project.msa_date}` |
| Loop | `{#items}...{/items}` | `{#services}...{/services}` |
| Rich text/HTML | `{~~formatted_field}` | `{~~project.formatted_executive_summary}` |
| Comparison | `{#field=="value"}...{/field=="value"}` | `{#slug=="tech_solution"}...{/slug=="tech_solution"}` |
| Image | `{%image_field}` | `{%project.account_logo}` |

### Current Item Reference

Within a loop, use `{.}` to reference the current item:

```
{#formatted_sentences}
{.}
{/formatted_sentences}
```

## Formatting Options

### With Formatting Enabled

When "Formatting for Tag Templates" is enabled in ScopeStack:

**Date Wrappers:**
- `.to_short_date` - Short date format
- `.to_formatted_time` - Time format

**Currency Wrappers:**
- `.to_currency` - Currency formatting (follows project rate table)

**Value Wrapper:**
- `.value` - Raw value without formatting

**Example:**
```
{project.printed_on.to_short_date}
{hourly_rate.to_currency}
```

### With Formatting Disabled

When formatting is disabled, use DocxTemplater filters:

**Number Formatting:**
```
{hourly_rate*1 | toFixed:2}
```

**Currency with Symbol:**
```
{currency.unit}{hourly_rate*1 | toFixed:2}
```

Note: Multiply by 1 to convert string to number before using `toFixed`

## Common Patterns

### Conditional with Else

```
{#project.msa_date}
The client signed an MSA on {project.msa_date}
{/project.msa_date}
{^project.msa_date}
The Client doesn't have an MSA with our company.
{/project.msa_date}
```

### Nested Conditionals with Name Check

```
{#language_fields}
  {#name=="Deliverables"}
    Deliverables:
    {~~formatted_sentences}
  {/name=="Deliverables"}
{/language_fields}
```

### Slug Comparisons

```
{#slug=="tech_solution"}
  Content for tech solution
{/slug=="tech_solution"}
```

### Filtering in Loops

```
{#project_pricing.resources}{^resource_slug=="project_total"}
  {resource_name}: {total | toFixed:2}
{/resource_slug=="project_total"}{/project_pricing.resources}
```

## Project-Level Fields

### Basic Project Info
```
{project.project_name}
{project.client_name}
{project.account_name}
{project.printed_on}
{project.created_on}
{project.msa_date}
```

### Formatted Narrative Fields
```
{~~project.formatted_executive_summary}
{~~project.formatted_solution_summary}
{~~project.formatted_our_responsibilities}
{~~project.formatted_customer_responsibilities}
{~~project.formatted_out_of_scope}
```

### Version Info
```
{project.current_version.name}
{project.current_version.comment}
{project.current_version.created_by}
```

### Sales Executive
```
{#project.sales_executive}
  {name} - {email}
{/project.sales_executive}
```

### Primary Contact
```
{#project.primary_contact}
  {name} - {email} - {phone}
{/project.primary_contact}
```

## Pricing Fields

### Summary
```
{project_pricing.total_contract_value*1 | toFixed:2}
{project_pricing.total_service_revenue*1 | toFixed:2}
{project_pricing.total_contract_cost*1 | toFixed:2}
{project_pricing.total_contract_profit*1 | toFixed:2}
{project_pricing.total_contract_margin}
```

### Resources Loop
```
{#project_pricing.resources}
  {resource_name}: {hourly_rate*1 | toFixed:2}
{/project_pricing.resources}
```

### Professional Services Phases
```
{#project_pricing.professional_services.phases}
  Phase: {name}
  {#services}
    Service: {name}
    Hours: {total_hours}
    Revenue: {total_revenue*1 | toFixed:2}
  {/services}
{/project_pricing.professional_services.phases}
```

## Language Fields Structure

Language fields contain phase-specific content:

```
{#language_fields}
  {#phases}
    {#slug=="inhouse_prep_language"}
      Inhouse Prep Content
    {/slug=="inhouse_prep_language"}
    
    {#slug=="onsite_implement_language"}
      Onsite Implementation Content  
    {/slug=="onsite_implement_language"}
    
    {#slug=="remote_implement_language"}
      Remote Implementation Content
    {/slug=="remote_implement_language"}
    
    {#slug=="post_support_langauge"}
      Post Support Content
    {/slug=="post_support_langauge"}
  {/phases}
{/language_fields}
```

## Common Issues

### ❌ Curly Quotes
**Wrong:** `{#name=="Deliverables"}`
**Correct:** `{#name=="Deliverables"}`

Use straight quotes, not curly/smart quotes!

### ❌ Missing Loop Closures
**Wrong:**
```
{#items}
  {name}
```

**Correct:**
```
{#items}
  {name}
{/items}
```

### ❌ Formatted Fields Not Rendering
**Wrong:** `{formatted_sentences}`
**Correct:** `{~~formatted_sentences}`

Use `~~` prefix for HTML/markdown fields!

### ❌ Number Formatting Fails
**Wrong:** `{total | toFixed:2}`
**Correct:** `{total*1 | toFixed:2}`

Multiply by 1 to convert string to number first!

## Best Practices

✅ **Use plain quotes** - Never use curly quotes in comparisons
✅ **Close all loops** - Every `{#...}` needs a matching `{/...}`
✅ **HTML fields need ~~** - All formatted_* fields need the ~~ prefix
✅ **Convert strings to numbers** - Use *1 or +0 before number filters
✅ **Clean paragraphs** - Place tags in their own clean paragraphs
✅ **Avoid nested styling** - Don't put tags inside bullets or pre-styled elements

## Conversion Mapping Reference

From our template converter:

### Simple Fields
```
Old: =client_name
New: {project.client_name}
```

### Loops with Sentences
```
Old: executive_summary:each(sentence)
     =sentence
     executive_summary:endEach
     
New: {#project.formatted_executive_summary}
     {.}
     {/project.formatted_executive_summary}
```

### Phase-Based Conditionals
```
Old: phase.inhouse_prep_language?:if
     ...content...
     phase.inhouse_prep_language?:endIf
     
New: {#slug=="inhouse_prep_language"}
     ...content...
     {/slug=="inhouse_prep_language"}
```

### Pricing Conditionals
```
Old: pricing.total_row?.present?:if
     ...content...
     pricing.total_row?.present?:endIf
     
New: {#resource_slug=="project_total"}
     ...content...
     {/resource_slug=="project_total"}
```

## Resources

- [Official ScopeStack Documentation](https://scopestack.io)
- [DocxTemplater Filters](https://docxtemplater.com/docs/angular-parse/#filters)
- Project merge data: View in ScopeStack → Project → Gear icon → "View Merge Data" (V2)

---

**Note:** This reference is based on ScopeStack's help articles and reflects the correct V2 Tag Template syntax.
