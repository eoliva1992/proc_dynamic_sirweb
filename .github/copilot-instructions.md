# Copilot Instructions — proc_dynamic_sirweb

## Graphify knowledge graph

This project maintains a knowledge graph at `graphify-out/graph.json`.

**Before answering any question about the codebase architecture, data flow, relationships between files, or "how does X work", always consult the graph first:**

- Use `/graphify query "<question>"` for broad codebase questions
- Use `/graphify path "<A>" "<B>"` to trace relationships between two concepts
- Use `/graphify explain "<concept>"` for focused explanations of a single module

**When to use it:**
- "How does X work?" → `graphify query "how does X work"`
- "What calls Y?" → `graphify query "what calls Y"`
- "How are A and B related?" → `graphify path "A" "B"`
- Architecture / data flow questions → read `graphify-out/GRAPH_REPORT.md`

**After modifying code**, remind the user to run `graphify update .` to keep the graph current (code-only, no API cost, runs in seconds).

Do NOT browse raw source files speculatively when the graph can answer the question faster and more precisely.

## graphify

For any question about this repo's architecture, structure, components, or how to add/modify/find
code, your first action should be `graphify query "<question>"` when `graphify-out/graph.json`
exists. Use `graphify path "<A>" "<B>"` for relationship questions and `graphify explain "<concept>"`
for focused-concept questions. These return a scoped subgraph, usually much smaller than the full
report or raw grep output.

Triggers: "how do I…", "where is…", "what does … do", "add/modify a <component>",
"explain the architecture", or anything that depends on how files or classes relate.

If `graphify-out/wiki/index.md` exists, use it for broad navigation. Read `graphify-out/GRAPH_REPORT.md`
only for broad architecture review or when query/path/explain do not surface enough context. Only read
source files when (a) modifying/debugging specific code, (b) the graph lacks the needed detail, or
(c) the graph is missing or stale.

Type `/graphify` in Copilot Chat to build or update the graph.
