import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

// This runs against `vite preview` with no backend behind it — the fetch to /api/items
// fails, and the component's own error path (role="alert") renders. That is
// deliberate: gate 15 exists to catch a BLANK built artifact and a broken accessibility
// tree, and both properties hold whether or not the API call itself succeeds. Wiring a
// real backend into this job is exactly the FULL-tier cost tasks.md Task 23b tiers away
// from being required on day one.
test("the page renders its main heading and form", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Items" })).toBeVisible();
  await expect(page.getByLabel("New item")).toBeVisible();
});

test("has no automatically detectable accessibility violations", async ({ page }) => {
  await page.goto("/");
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa"])
    .analyze();

  // The known-violations baseline. EMPTY on purpose — see docs/QUALITY-GATES.md.
  const knownViolations: string[] = [];
  const unexpected = results.violations.filter(
    (v) => !knownViolations.includes(v.id),
  );

  expect(unexpected, JSON.stringify(unexpected, null, 2)).toEqual([]);
});
