# Library setup format

The Library tab is a list of rows that the listener sets up. This is the stored form of that list. Klassik keeps it
in the device file of each server account, under the key `library`, next to favourites and notes. The format is plain
JSON, so that an export or the iCloud sync can carry it without code from the app.

`schema.json` is the JSON Schema (draft 2020-12) of version 1. `example.json` is a valid document.
`scripts/library_setup_check.py` checks the schema, the example and the Swift enum names. The `library-setup` job of
`test.yml` runs it.

## Document

| Field     | Type   | Meaning                                       |
|-----------|--------|-----------------------------------------------|
| `version` | number | The format version. Version 1 is described here. |
| `rows`    | array  | The rows in tab order, top first.             |

## Row

| Field        | Meaning                                                                                        |
|--------------|------------------------------------------------------------------------------------------------|
| `id`         | A string, unique in the document. The app writes a UUID, and `default-<kind>` for default rows. |
| `kind`       | `pick` (Daily pick), `composers`, `performers`, `works`, `recordings`, `albums`, `favourites`, `added` (Recently added), `heard` (Recently heard), `saved` (Saved search) or `links` (Link list). |
| `source`     | What the row lists: `library`, `composers`, `performers`, `works`, `recordings` or `albums`. The five kinds that list one thing name it. The other kinds use `library`. |
| `searchText` | The search text of a saved search row, or of the saved search that a Daily pick draws from.      |
| `conditions` | The filter. Terms of one condition join with "or"; conditions join with "and". A term is `{"kind": "genre" or "composer" or "conductor" or "performer", "name": "..."}`. |
| `sort`       | `random`, `best` (Best known), `newest`, `heard` or `az`.                                       |
| `form`       | `faces`, `covers` or `tiles`.                                                                   |
| `count`      | Items shown: 6, 9 or 12 for a strip, 3, 6 or 9 for tiles.                                        |
| `links`      | The checked links of a link list, in order. Empty for other kinds.                              |

A document holds at most one row of kind `pick`.

## Reading

- A reader refuses a document with a `version` that it does not know. It shows its default rows, and it never writes
  over the document.
- A reader drops a row that it cannot read: an unknown `kind`, an unknown value, a repeated `id`, or a second `pick`.
- A reader fills a missing field with the start value of the row's kind.

## Changing the format

A change that old readers can still read, such as a new optional field, keeps the version. Any other change raises
`version`, changes `schema.json` and `example.json` in the same commit, and keeps a reader for the old version.
