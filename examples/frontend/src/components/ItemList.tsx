import { useEffect, useState } from "react";
import { createItem, fetchItems, markItemDone, type Item } from "../api";

/**
 * The bundled example product's one frontend component. Talks to the backend's
 * /api/items resource — see backend/src/main/java/com/example/agentsdlc/web.
 * Accessible by construction: a labelled form control, a semantic list, and a visible
 * focus state (inherited from the browser default, never suppressed) — gate 15's
 * accessibility baseline ships empty, and this is what keeps it that way.
 */
export function ItemList() {
  const [items, setItems] = useState<Item[]>([]);
  const [title, setTitle] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchItems().then(setItems).catch((e: Error) => setError(e.message));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) {
      setError("Title must not be blank.");
      return;
    }
    try {
      const created = await createItem(title.trim());
      setItems((prev) => [...prev, created]);
      setTitle("");
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function handleMarkDone(id: number) {
    const updated = await markItemDone(id);
    setItems((prev) => prev.map((it) => (it.id === id ? updated : it)));
  }

  return (
    <main>
      <h1>Items</h1>
      <form onSubmit={handleSubmit}>
        <label htmlFor="item-title">New item</label>
        <input
          id="item-title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <button type="submit">Add</button>
      </form>
      {error && <p role="alert">{error}</p>}
      <ul aria-label="Items">
        {items.map((item) => (
          <li key={item.id}>
            <span>{item.title}</span>{" "}
            {item.done ? (
              <span>(done)</span>
            ) : (
              <button type="button" onClick={() => handleMarkDone(item.id)}>
                Mark done
              </button>
            )}
          </li>
        ))}
      </ul>
    </main>
  );
}
