export interface Item {
  id: number;
  title: string;
  done: boolean;
}

// Same-origin `/api` — the backend serves this build in production; the dev server
// proxies it (see vite.config.ts). Kept as a named export so tests can mock it without
// reaching into module internals.
const BASE = "/api/items";

export async function fetchItems(): Promise<Item[]> {
  const res = await fetch(BASE);
  if (!res.ok) throw new Error(`fetchItems failed: ${res.status}`);
  return res.json();
}

export async function createItem(title: string): Promise<Item> {
  const res = await fetch(BASE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });
  if (!res.ok) throw new Error(`createItem failed: ${res.status}`);
  return res.json();
}

export async function markItemDone(id: number): Promise<Item> {
  const res = await fetch(`${BASE}/${id}/done`, { method: "PUT" });
  if (!res.ok) throw new Error(`markItemDone failed: ${res.status}`);
  return res.json();
}
