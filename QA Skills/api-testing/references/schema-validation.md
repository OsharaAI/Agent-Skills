# Schema Validation — Zod, AJV, Contract

This file holds the runnable schema-validation code. The reasoning about when to validate a schema and why schema-as-contract matters lives in `SKILL.md`.

## Zod (Zod 4 native form)

> **Zod 4 vs Zod 3.** Zod 4 introduced significant API changes. Three worth knowing: (1) **String formats are now top-level functions** — `z.email()`, `z.uuid()`, `z.iso.datetime()` replace the older chained `z.string().email()`, `z.string().uuid()`, `z.string().datetime()`. The chained versions still function but log deprecation warnings and are on track for removal in the next major release, so prefer the new form going forward. (2) `z.coerce` syntax and error formatting both changed — if a codebase has both Zod 3 and 4 packages installed, anything consuming the error format can silently break, so pin the version per package. (3) `z.uuid()` now enforces RFC 9562/4122 strictly; reach for `z.guid()` instead if you want a looser "UUID-like" check. When generating Zod from OpenAPI, **`orval`** and **`openapi-zod-client`** are the tools that stay maintained for round-tripping.

```typescript
import { z } from 'zod';
import { test, expect } from '@playwright/test';

const UserSchema = z.object({
  id: z.uuid(),
  email: z.email(),
  name: z.string().min(1),
  role: z.enum(['admin', 'member', 'viewer']),
  createdAt: z.iso.datetime(),
});

const UsersListSchema = z.object({
  users: z.array(UserSchema),
  total: z.number().int().nonnegative(),
  page: z.number().int().positive(),
  pageSize: z.number().int().positive(),
});

test('GET /api/users matches schema', async ({ request }) => {
  const response = await request.get('/api/users');
  const result = UsersListSchema.safeParse(await response.json());
  if (!result.success) console.error('Schema errors:', result.error.issues);
  expect(result.success).toBe(true);
});
```

## AJV with JSON Schema

```typescript
import Ajv from 'ajv';
import addFormats from 'ajv-formats';

const ajv = new Ajv({ allErrors: true });
addFormats(ajv);

const userSchema = {
  type: 'object',
  required: ['id', 'email', 'name', 'role'],
  properties: {
    id: { type: 'string', format: 'uuid' },
    email: { type: 'string', format: 'email' },
    name: { type: 'string', minLength: 1 },
    role: { type: 'string', enum: ['admin', 'member', 'viewer'] },
  },
  additionalProperties: false,
};

test('GET /api/users/:id conforms to JSON Schema', async ({ request }) => {
  const body = await (await request.get('/api/users/some-valid-id')).json();
  expect(ajv.compile(userSchema)(body)).toBe(true);
});
```

## Schema-as-Contract Pattern

Have the API implementation and its tests import one shared schema file. The moment the response shape changes, consumer tests fail right away. Given an OpenAPI spec, generate that schema with `orval` or `openapi-zod-client` (the tools that stay maintained for round-tripping) so the contract never drifts from the spec.

```typescript
// shared/schemas/user.schema.ts  (imported by both API and tests)
import { z } from 'zod';
export const UserResponseSchema = z.object({
  id: z.uuid(),
  email: z.email(),
  name: z.string(),
  role: z.enum(['admin', 'member', 'viewer']),
  createdAt: z.iso.datetime(),
});
export type UserResponse = z.infer<typeof UserResponseSchema>;
```

## Spec-Driven & Property-Based Validation

With an OpenAPI spec in hand, you can push validation further than hand-written schemas allow. **Schemathesis** (Python, built on Hypothesis) generates large numbers of test cases straight from the spec, uncovering 500s on edge-case inputs, undocumented response shapes, and validation gaps — all without maintaining tests per endpoint. Point it at the live API and its spec:

```bash
schemathesis run http://localhost:3000/openapi.json --checks all
```

Best run as a CI job for teams that are spec-first; it supplements rather than replaces the targeted happy/error-path tests found in `test-patterns.md`.
