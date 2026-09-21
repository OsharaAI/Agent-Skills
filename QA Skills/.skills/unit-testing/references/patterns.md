# Unit Testing Patterns — reference examples

This is the code that backs up the guidance in SKILL.md. Each section below is cited
from a specific spot in that file — there's no new guidance here, just runnable,
copy-ready examples per framework.

---

## Jest

### A describe block with setup/teardown and a typed mock

```typescript
describe("UserService", () => {
  let service: UserService;
  let mockRepo: jest.Mocked<UserRepository>;

  beforeEach(() => {
    mockRepo = { findById: jest.fn(), save: jest.fn() } as jest.Mocked<UserRepository>;
    service = new UserService(mockRepo);
  });
  afterEach(() => jest.restoreAllMocks());

  it("should return user when found", async () => {
    // Arrange
    mockRepo.findById.mockResolvedValue({ id: "1", name: "Alice" });
    // Act
    const result = await service.getUser("1");
    // Assert
    expect(result).toEqual({ id: "1", name: "Alice" });
  });

  it("should throw when user not found", async () => {
    mockRepo.findById.mockResolvedValue(null);
    await expect(service.getUser("999")).rejects.toThrow(NotFoundError);
  });
});
```

### Mocking a whole module (`jest.mock`)

```typescript
jest.mock("./email-client", () => ({
  sendEmail: jest.fn().mockResolvedValue({ sent: true }),
}));
// Partial mock — keep original, override one export
jest.mock("./utils", () => ({ ...jest.requireActual("./utils"), generateId: jest.fn(() => "fixed") }));
```

### Spying (`jest.spyOn`) — keeps the real implementation, just records calls

```typescript
const spy = jest.spyOn(console, "warn").mockImplementation();
service.deprecatedMethod();
expect(spy).toHaveBeenCalledWith(expect.stringContaining("deprecated"));
```

### Working with fake timers

```typescript
beforeEach(() => jest.useFakeTimers());
afterEach(() => jest.useRealTimers());

it("should debounce", () => {
  const fn = jest.fn();
  const debounced = debounce(fn, 300);
  debounced();
  expect(fn).not.toHaveBeenCalled();
  jest.advanceTimersByTime(300);
  expect(fn).toHaveBeenCalledTimes(1);
});
```

**Fake only what you need.** Faking *every* timer can deadlock code that's waiting on a
genuine microtask (say, an `await fetch` that's mocked to resolve). Scope the fake down:

```typescript
jest.useFakeTimers({ doNotFake: ["nextTick", "queueMicrotask"] });
// Vitest equivalent: vi.useFakeTimers({ toFake: ["setTimeout", "Date"] })
```

### Async tests — assert on the promise directly

```typescript
await expect(fn()).resolves.toEqual({ ok: true });
await expect(fn()).rejects.toThrow(ValidationError);
```

Protect async tests from passing vacuously — a dropped `await` means the assertion
inside never runs, and the test goes green having checked nothing:

```typescript
it("rejects bad input", async () => {
  expect.assertions(1); // fails the test if no assertion actually ran
  await expect(validate("")).rejects.toThrow();
});
```

---

## Vitest

The API surface matches Jest closely, but it's built Vite-native. Configuration:

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "lcov"],
      thresholds: { branches: 80, functions: 80, lines: 80, statements: 80 },
      // changed: true,  // Vitest 4.1+: coverage only for files in the diff — big CI win on large repos
    },
  },
});
```

### Mocking with `vi`

```typescript
vi.mock("./email-client", () => ({ sendConfirmation: vi.fn().mockResolvedValue(true) }));
const spy = vi.spyOn(repository, "save");
```

### In-source testing (handy for small utility functions)

```typescript
export function clamp(val: number, min: number, max: number) {
  return Math.min(Math.max(val, min), max);
}
if (import.meta.vitest) {
  const { it, expect } = import.meta.vitest;
  it("clamps below", () => expect(clamp(-5, 0, 10)).toBe(0));
  it("clamps above", () => expect(clamp(15, 0, 10)).toBe(10));
}
```

To enable it: set `test: { includeSource: ["src/**/*.ts"] }` and
`define: { "import.meta.vitest": "undefined" }` — the `define` entry is what strips
this block out of the production bundle.

### Monorepo workspaces

```typescript
// vitest.workspace.ts
export default ["packages/*/vitest.config.ts"];
```

### Running tests concurrently

`describe.concurrent` / `it.concurrent` run sibling tests within a file in parallel.
Only apply this to tests with no shared mutable state — concurrent tests touching the
same fixture will race each other. Note that **Vitest 5 beta removes the `sequential`
option entirely**, so forcing order there means removing `.concurrent`, not flipping a
setting. Also, each concurrent test needs to pull `expect` from its own local context
(`it.concurrent("x", async ({ expect }) => …)`), otherwise assertions can leak across
tests.

### Browser mode (Vitest 4+)

This runs component-level tests inside an actual browser (via Playwright or
WebdriverIO) rather than JSDOM. Reach for it when JSDOM produces false positives around
layout, focus, or paint behavior — functionally it overlaps with Cypress component
testing.

```typescript
// vitest.config.ts (browser mode)
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: {
    browser: { enabled: true, provider: "playwright", name: "chromium" },
  },
});
```

---

## pytest

### Fixtures and conftest.py

```python
# conftest.py
@pytest.fixture
def db():
    database = Database(":memory:")
    database.migrate()
    yield database
    database.close()

@pytest.fixture
def user_service(db):
    return UserService(db)
```

```python
class TestUserService:
    def test_create_returns_id(self, user_service):
        uid = user_service.create({"name": "Alice"})
        assert uid is not None

    def test_get_nonexistent_raises(self, user_service):
        with pytest.raises(UserNotFoundError):
            user_service.get("nonexistent")
```

### Using parametrize for data-driven cases

```python
@pytest.mark.parametrize("input_val,expected", [
    ("hello world", "Hello World"), ("", ""), ("CAPS", "Caps"),
])
def test_title_case(input_val, expected):
    assert title_case(input_val) == expected
```

### Substituting values with monkeypatch

```python
def test_uses_env(monkeypatch):
    monkeypatch.setenv("APP_URL", "https://test.local")
    assert fetch_config()["source"] == "https://test.local"

def test_retry(monkeypatch):
    calls = {"n": 0}
    def fake(url):
        calls["n"] += 1
        if calls["n"] < 3: raise ConnectionError
        return {"ok": True}
    monkeypatch.setattr("app.client.http_request", fake)
    assert fetch_with_retry("https://api.test") == {"ok": True}
```

**Markers:** tag slow tests with `@pytest.mark.slow`, then exclude them via
`pytest -m "not slow"`. For matching by name, use `-k "test_create"`.

---

## Bun test / Deno test

- **`bun test`** — solid enough for a greenfield project on the Bun stack: a
  Jest-compatible API, esbuild-fast, and no separate runner config needed beyond
  `package.json`'s `scripts.test`.
- **`deno test`** — Deno's built-in runner: permission flags plus native TypeScript
  support.

Both are sensible defaults when the runtime is already Bun or Deno; for Node projects,
Vitest or Jest still make more sense given their deeper plugin ecosystems.

---

## The four test doubles, in code

```typescript
// Stub — just a return value, no verification
const pricing = { getPrice: () => 9.99 };

// Spy — real behavior, calls tracked
const spy = vi.spyOn(logger, "info");

// Mock — replaced impl + interaction verified
const notifier = { send: vi.fn().mockResolvedValue(true) };
expect(notifier.send).toHaveBeenCalledWith(expect.objectContaining({ type: "done" }));

// Fake — working substitute (in-memory implementation)
class FakeRepo implements UserRepository {
  private data = new Map<string, User>();
  async findById(id: string) { return this.data.get(id) ?? null; }
  async save(u: User) { this.data.set(u.id, { ...u }); }
}
```

---

## Snapshot testing — file vs. inline, plus property matchers

```typescript
// File snapshot — stored in __snapshots__/*.snap
expect(tree).toMatchSnapshot();

// Inline snapshot — stored in the test file, auto-updated on first run
expect(tree).toMatchInlineSnapshot(`<header><h1>Dashboard</h1></header>`);

// Property matchers for dynamic values — keeps the snapshot stable
expect(user).toMatchSnapshot({ id: expect.any(String), createdAt: expect.any(Date) });
```

Favor inline snapshots when the output is short (under 20 lines). And always run CI
with `--ci` so that an unrecognized snapshot **fails** the run instead of being written
and committed without anyone noticing.
