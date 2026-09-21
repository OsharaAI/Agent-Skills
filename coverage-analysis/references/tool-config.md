# Coverage Tool Configuration

Concrete configuration for Vitest (V8/Istanbul), the c8 CLI (non-Vitest runners), nyc, Jest, and coverage.py. Rationale and version notes live in `SKILL.md`; this file is just the config.

## Vitest — V8 provider (default)

V8's coverage support is built directly into the engine and skips instrumenting your source, which is why it beats Istanbul on speed. In a **Vitest** project, install the provider package — `@vitest/coverage-v8` — and skip `c8` entirely. (c8 exists as a standalone CLI for runners that aren't Vitest; see the next section.)

```bash
npm i -D @vitest/coverage-v8   # Node 20+ baseline
# Seeing bad line attribution through your bundler? swap to: npm i -D @vitest/coverage-istanbul
```

```json
// package.json
{
  "scripts": {
    "test": "vitest run",
    "test:coverage": "vitest run --coverage"
  }
}
```

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",   // or "istanbul" — install @vitest/coverage-istanbul
      reporter: ["text", "html", "lcov", "json-summary"],
      reportsDirectory: "./coverage",
      include: ["src/**/*.ts"],
      exclude: [
        "src/**/*.test.ts",
        "src/**/*.spec.ts",
        "src/**/*.d.ts",
        "src/**/index.ts",       // Barrel exports
        "src/**/types.ts",       // Type-only files
        "src/**/*.stories.ts",   // Storybook
        "src/generated/**",      // Generated code
      ],
      thresholds: {
        lines: 80,
        branches: 80,
        functions: 80,
        statements: 80,
      },
    },
  },
});
```

## c8 CLI — for non-Vitest Node runners

Working with `node:test`, bare mocha, or any runner that lacks its own coverage integration? `c8` wraps that same underlying V8 data as a plain CLI wrapper. Skip installing c8 inside a Vitest project — Vitest already gets its V8 support through `@vitest/coverage-v8`.

```bash
npm i -D c8@^11   # current major; c8 11 supports Node >=12
```

```jsonc
// .c8rc.json (or "c8" key in package.json)
{
  "reporter": ["text", "html", "lcov", "json-summary"],
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.test.ts", "src/**/*.d.ts", "src/**/index.ts", "src/generated/**"],
  "check-coverage": true,
  "branches": 80,
  "lines": 80,
  "functions": 80,
  "statements": 80
}
```

```bash
c8 node --test            # run node:test under coverage
c8 mocha                  # or wrap any runner
```

## Istanbul / nyc (JavaScript/TypeScript)

Istanbul takes the slower route of instrumenting source directly, which costs speed but tracks more reliably across transpilers and bundlers.

```bash
npm i -D nyc@^18   # nyc 18 requires Node 20 || >= 22; pin nyc@^17 to stay on Node 18
```

```json
// .nycrc.json
{
  "all": true,
  "include": ["src/**/*.ts"],
  "exclude": [
    "src/**/*.test.ts",
    "src/**/*.spec.ts",
    "src/**/*.d.ts",
    "src/**/index.ts",
    "src/generated/**"
  ],
  "reporter": ["text", "html", "lcov", "json-summary"],
  "report-dir": "./coverage",
  "check-coverage": true,
  "branches": 80,
  "lines": 80,
  "functions": 80,
  "statements": 80,
  "watermarks": {
    "lines": [70, 90],
    "functions": [70, 90],
    "branches": [70, 90],
    "statements": [70, 90]
  }
}
```

## Jest

Jest comes with coverage support out of the box — nothing extra to install. Set `coverageProvider` to `"v8"` (quicker, skips Babel) or `"babel"` (Istanbul under the hood; reach for it when V8 mismaps lines through your transform).

```json
// package.json (with Jest)
{
  "scripts": {
    "test:coverage": "jest --coverage"
  },
  "jest": {
    "coverageProvider": "v8",
    "collectCoverageFrom": [
      "src/**/*.ts",
      "!src/**/*.{test,spec,d}.ts",
      "!src/**/index.ts",
      "!src/generated/**"
    ],
    "coverageThreshold": {
      "global": {
        "branches": 80,
        "functions": 80,
        "lines": 80,
        "statements": 80
      }
    }
  }
}
```

## coverage.py (Python)

```bash
pip install pytest-cov   # current coverage.py 7.14.x
```

> coverage.py 7.13.0 introduced `.coveragerc.toml` as a standalone TOML-first config file — a good pick for new Python projects that want coverage config kept apart from `pyproject.toml`. 7.12.0 started reporting statements and branches as separate totals in HTML and JSON output.

```toml
# pyproject.toml (or .coveragerc.toml in 7.13+)
[tool.coverage.run]
source = ["src"]
branch = true
omit = [
    "src/**/test_*.py",
    "src/**/conftest.py",
    "src/**/__init__.py",
    "src/generated/*",
]

[tool.coverage.report]
fail_under = 80
show_missing = true
skip_covered = true
precision = 1
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "if __name__ == .__main__.",
    "raise NotImplementedError",
    "@overload",
    "\\.\\.\\.",     # Ellipsis in abstract methods
]

[tool.coverage.html]
directory = "coverage/html"

[tool.coverage.xml]
output = "coverage/coverage.xml"
```

```bash
# Run tests with coverage
pytest --cov=src --cov-report=term-missing --cov-report=html --cov-report=xml

# Fail if coverage drops below threshold
pytest --cov=src --cov-fail-under=80
```
