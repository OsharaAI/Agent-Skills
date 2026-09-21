# Clustering Near-Duplicate Tests

Combining AST-based similarity with coverage-profile signatures, then grouping the
results at a tunable threshold. The rule that every cluster goes to a human — never
straight to auto-deletion — is set out in `SKILL.md` §3.

## 1. Parse each test into an AST and normalize it

Plain string comparison or a raw `diff` breaks down the moment variables get renamed or
code gets reformatted. Parsing to an AST and stripping out the noise — identifier names,
literal values — means two copy-pasted tests with different variable names will still
match structurally.

```python
import ast

class Normalizer(ast.NodeTransformer):
    """Erase identifier names and literals; keep structure."""
    def visit_Name(self, node):
        return ast.copy_location(ast.Name(id="VAR", ctx=node.ctx), node)
    def visit_Constant(self, node):
        return ast.copy_location(ast.Constant(value="CONST"), node)

def ast_tokens(src: str) -> list[str]:
    tree = Normalizer().visit(ast.parse(src))
    ast.fix_missing_locations(tree)
    # Dump node-type sequence as the structural token stream.
    return [type(n).__name__ for n in ast.walk(tree)]
```

(In JS/TS, reach for `@babel/parser` or `ts-morph` and apply the same
normalize-then-walk pattern.)

## 2. Scoring similarity

Score similarity over tokens or trees — Jaccard over shingles, cosine over n-grams, or
tree edit distance. Line numbers should never be used as a similarity signal.

```python
def shingles(tokens, k=3):
    return {tuple(tokens[i:i+k]) for i in range(len(tokens) - k + 1)}

def jaccard(a: set, b: set) -> float:
    if not a and not b:
        return 1.0
    return len(a & b) / len(a | b)

def ast_similarity(src_a, src_b, k=3):
    return jaccard(shingles(ast_tokens(src_a), k), shingles(ast_tokens(src_b), k))
```

Tree edit distance (via the `zss` package's Zhang-Shasha implementation) is more exact
but runs O(n²) per pair — save it for confirming pairs that the cheaper Jaccard score
already surfaced.

## 3. Fold in the coverage-profile signature

Every test already carries a covered-line/branch set — its **execution profile** — from
`coverage-fingerprinting.md`. Require *both* signals to agree — near-identical AST *and*
near-identical coverage profile — so that tests which merely look similar in structure
but actually exercise different paths don't get merged by mistake.

```python
def combined_score(a, b, src, cov_sets, w_ast=0.6, w_cov=0.4):
    s_ast = ast_similarity(src[a], src[b])
    s_cov = jaccard(cov_sets[a], cov_sets[b])
    return w_ast * s_ast + w_cov * s_cov
```

## 4. Group at a tunable threshold

```python
from scipy.cluster.hierarchy import linkage, fcluster
from scipy.spatial.distance import squareform
import numpy as np

def cluster(tests, src, cov_sets, threshold=0.85):
    n = len(tests)
    dist = np.zeros((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            sim = combined_score(tests[i], tests[j], src, cov_sets)
            dist[i, j] = dist[j, i] = 1 - sim
    # agglomerative / hierarchical clustering; cut at the configurable cutoff
    Z = linkage(squareform(dist), method="average")
    labels = fcluster(Z, t=1 - threshold, criterion="distance")
    clusters = {}
    for test, label in zip(tests, labels):
        clusters.setdefault(label, []).append(test)
    return {k: v for k, v in clusters.items() if len(v) > 1}
```

A threshold around 0.85 is a reasonable starting point; tune from there based on how
many false positives you're willing to sift through — lowering it surfaces more
candidates but also more pairs that are only superficially alike.

## 5. Output clusters — never delete from them directly

For each cluster, report its members, the pairwise AST similarity, the coverage-profile
overlap, and where the assertions actually differ. Send it to a human for review. The
agent should never remove an entire cluster on its own — copy-pasted tests routinely
diverge in the one assertion that actually matters.
