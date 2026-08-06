import js from "@eslint/js";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import tseslint from "typescript-eslint";

// Gate 6 — lint at zero warnings, INCLUDING FRAMEWORK-CORRECTNESS RULES
// (react-hooks/rules-of-hooks, exhaustive-deps): those catch dead code and stale-closure
// bugs that otherwise need production traffic to surface. `npm run lint -- --max-warnings 0`
// is what makes a warning here a build failure, not this file.
export default tseslint.config(
  { ignores: ["dist", "coverage", "reports", "playwright-report"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
    },
  },
  {
    files: ["**/*.test.{ts,tsx}", "src/setupTests.ts"],
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
    },
  },
  {
    files: ["*.config.{js,ts,mjs}", "scripts/**/*.mjs", "e2e/**/*.ts"],
    languageOptions: {
      globals: globals.node,
    },
  },
);
