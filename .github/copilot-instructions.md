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
