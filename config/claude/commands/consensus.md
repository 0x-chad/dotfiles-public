Use this command when you need a second opinion on a decision, approach, or implementation.

Get consensus on the topic or question provided in $ARGUMENTS using multiple AI perspectives:

1. First, write a concise independent analysis of the question and the likely tradeoffs.
2. Then, if the `codex` CLI is available, ask Codex for a second opinion from the current repository directory.
3. Compare both responses and synthesize a final consensus, noting:
   - Points of agreement
   - Points of disagreement
   - Recommended approach based on the combined insights

If $ARGUMENTS is empty, ask what topic or question needs consensus.

Important: Run this from a git repository directory (Codex CLI requires it).
