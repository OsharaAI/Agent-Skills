# Schema-First Contract Testing — Code

This file holds the implementation side of the schema-first (OpenAPI) approach and of spec-driven property testing with Schemathesis. For the trade-offs and guidance on when to reach for each, see `SKILL.md`.

## Schema-First (OpenAPI + Validation)

The provider publishes an OpenAPI spec, and consumers check their own usage against it.

> **Don't assume OpenAPI 3.0 is plain JSON Schema.** It relies on `nullable: true` and other keywords a vanilla Ajv instance won't understand, since Ajv defaults to the 2020-12 draft — it will either throw or silently mis-validate a genuine 3.0 spec. Configure Ajv for the OpenAPI dialect and bring in `ajv-formats` to cover formats like `date-time`, `email`, and `uri`. If you're on OpenAPI 3.1 instead (which really is valid JSON Schema 2020-12), plain Ajv with `ajv-formats` is sufficient on its own. For 3.0, the cleanest option is a purpose-built validator such as `openapi-response-validator`; the snippet below demonstrates the Ajv route along with the config it needs.

```typescript
// Schema-first: validate a response against an OpenAPI 3.0 operation schema
import SwaggerParser from "@apidevtools/swagger-parser";
import Ajv from "ajv";
import addFormats from "ajv-formats";
import type { OpenAPIV3 } from "openapi-types";

// strict:false tolerates OpenAPI's nullable/discriminator extensions on the 3.0 dialect
const ajv = new Ajv({ strict: false, allErrors: true });
addFormats(ajv);

// Walk paths to find the operation by operationId. Replace with your spec's shape
// if you index operations differently (e.g. by path+method).
function findOperation(spec: OpenAPIV3.Document, operationId: string): OpenAPIV3.OperationObject {
  for (const pathItem of Object.values(spec.paths)) {
    for (const op of Object.values(pathItem ?? {})) {
      if (op && typeof op === "object" && "operationId" in op && op.operationId === operationId) {
        return op as OpenAPIV3.OperationObject;
      }
    }
  }
  throw new Error(`No operation with operationId "${operationId}" in spec`);
}

async function validateAgainstSpec(response: unknown, operationId: string) {
  const spec = (await SwaggerParser.dereference("./openapi.yaml")) as OpenAPIV3.Document;
  const operation = findOperation(spec, operationId);
  const ok = operation.responses["200"] as OpenAPIV3.ResponseObject;
  const schema = ok.content?.["application/json"]?.schema;
  if (!schema) throw new Error(`No 200 application/json schema for ${operationId}`);

  const validate = ajv.compile(schema);
  if (!validate(response)) {
    throw new Error(`Response violates API spec: ${JSON.stringify(validate.errors)}`);
  }
}
```

## Schemathesis (Property-Based, Spec-Driven)

On OpenAPI-first projects, **Schemathesis** takes the spec and runs property-based tests directly against a live API — firing off thousands of both valid and invalid requests and checking that the responses stay conformant. It tends to catch a different class of bug than Pact does (encoding quirks, unusual edge-case payloads, status codes drifting out of spec).

The current major version is **v4.x** (released 2025-06). It made the schema a positional argument and moved the base URL to a `--url` flag:

```bash
# v4 form: schema is the positional arg, --url supplies the base URL
schemathesis run ./openapi.yaml --url https://api.example.com/v1 --checks all
```

> **Don't use `schemathesis run --base-url ... --hypothesis-deadline=2000` — that's Schemathesis ≤ v3 syntax, dead since v4.0 (2025-06).** v4 removed `--hypothesis-deadline` entirely and renamed `--base-url` to `--url`. Any command still using the old form will fail on Schemathesis ≥ 4.0. `--checks all` carries over unchanged into v4.

For CI, favor the maintained Action over hand-rolling a shell command — it pins the version for you and avoids breakage from flag changes:

```yaml
# .github/workflows/schemathesis.yml
- uses: schemathesis/action@v3
  with:
    schema: ./openapi.yaml
    base-url: https://staging.example.com/v1
    args: "--checks all"
```

Run Schemathesis alongside Pact rather than instead of it: Pact covers consumer-driven *interactions*, Schemathesis covers spec-driven *coverage*. There's some overlap, but each catches problems the other doesn't.
