# Release notes section

Load this file only when the PR template contains `REL_BOT_IDENTIFIER`. A CI bot parses the PR body for exact HTML comment markers. A missing, escaped or malformed marker fails the pipeline.

## Markers

The bot parses `<!---` (three dashes). The template may use two dashes. Write exactly these two markers with three dashes:

- `<!---REL_BOT_IDENTIFIER--->` (not `<!--REL_BOT_IDENTIFIER-->`)
- `<!---DO_NOT_DELETE--->` (not `<!--DO_NOT_DELETE-->`)

Every other HTML comment in the template (`<!---rel_bot_tag--->` or any `<!--...-->`) stays verbatim. Do not convert, move or remove it.

The temp file must contain the literal `<!---`, never `<\!---` or `&lt;!---`. The full-body verification diff in SKILL.md catches an escaped marker.

## Structure

```markdown
## Release Notes

<!---REL_BOT_IDENTIFIER--->
- <release note>
<!---DO_NOT_DELETE--->
```

## Length

The bot runs `${#release_notes} -lt 80`. That measures the whole text between the two markers as one string. The check source is not in this repo, so the rule is cautious: write every bullet with at least 80 characters after the `- ` prefix. A bullet of that length passes whether the bot counts per line or in total.

## Content

- Write from the user's perspective: what changed for them, not for the developer.
- One bullet per logical change.
- No internal jargon, class names or implementation details.
- Follow the [Writing Release Notes Guidelines](https://everlong.atlassian.net/wiki/spaces/REL/pages/5065441305/Writing+release+notes+-+guidelines) when the repo links them.

## Updating an existing PR

When the existing body already has text between the markers and the text is not the template placeholder, keep it verbatim. A person may have edited it. Write a new note only when the section is empty or still holds the placeholder.
