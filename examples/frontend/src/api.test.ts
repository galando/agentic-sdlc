// Gate 9 (frontend coverage) / the fetch wrapper every UI action goes through. ItemList.tsx
// catches rejections as `(e as Error).message` and renders it in a `role="alert"` element —
// so the contract under test isn't just "the right URL got called", it's "a caller that only
// knows how to read `.message` off a rejection gets something sane in every failure mode":
// a non-2xx response, a transport-level rejection (offline, DNS, CORS), and a response body
// that isn't valid JSON.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createItem, fetchItems, markItemDone } from "./api";

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(body),
  } as unknown as Response;
}

function brokenJsonResponse(status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.reject(new SyntaxError("Unexpected token < in JSON")),
  } as unknown as Response;
}

describe("api", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe("fetchItems", () => {
    it("GETs /api/items and resolves with the parsed array on success", async () => {
      const items = [{ id: 1, title: "buy milk", done: false }];
      vi.mocked(fetch).mockResolvedValue(jsonResponse(items));

      await expect(fetchItems()).resolves.toEqual(items);
      expect(fetch).toHaveBeenCalledWith("/api/items");
    });

    it("rejects with a message naming the status on a non-2xx response, without parsing the body", async () => {
      const res = jsonResponse({ error: "nope" }, 500);
      const jsonSpy = vi.spyOn(res, "json");
      vi.mocked(fetch).mockResolvedValue(res);

      await expect(fetchItems()).rejects.toThrow("fetchItems failed: 500");
      expect(jsonSpy).not.toHaveBeenCalled();
    });

    it("propagates a transport-level rejection (offline, DNS, CORS) as-is", async () => {
      const transportError = new TypeError("Failed to fetch");
      vi.mocked(fetch).mockRejectedValue(transportError);

      await expect(fetchItems()).rejects.toBe(transportError);
    });

    it("propagates a malformed-JSON body as a rejection rather than resolving with junk", async () => {
      vi.mocked(fetch).mockResolvedValue(brokenJsonResponse());

      await expect(fetchItems()).rejects.toThrow(/Unexpected token/);
    });
  });

  describe("createItem", () => {
    it("POSTs the title as JSON and resolves with the created item", async () => {
      const created = { id: 2, title: "wash car", done: false };
      vi.mocked(fetch).mockResolvedValue(jsonResponse(created, 201));

      await expect(createItem("wash car")).resolves.toEqual(created);
      expect(fetch).toHaveBeenCalledWith("/api/items", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: "wash car" }),
      });
    });

    it("rejects with a message naming the status on a non-2xx response", async () => {
      vi.mocked(fetch).mockResolvedValue(jsonResponse({}, 400));

      await expect(createItem("bad")).rejects.toThrow("createItem failed: 400");
    });

    it("propagates a transport-level rejection as-is", async () => {
      const transportError = new TypeError("Failed to fetch");
      vi.mocked(fetch).mockRejectedValue(transportError);

      await expect(createItem("x")).rejects.toBe(transportError);
    });
  });

  describe("markItemDone", () => {
    it("PUTs to the item's /done path and resolves with the updated item", async () => {
      const updated = { id: 3, title: "read book", done: true };
      vi.mocked(fetch).mockResolvedValue(jsonResponse(updated));

      await expect(markItemDone(3)).resolves.toEqual(updated);
      expect(fetch).toHaveBeenCalledWith("/api/items/3/done", { method: "PUT" });
    });

    it("rejects with a message naming the status on a non-2xx response", async () => {
      vi.mocked(fetch).mockResolvedValue(jsonResponse({}, 404));

      await expect(markItemDone(99)).rejects.toThrow("markItemDone failed: 404");
    });

    it("propagates a transport-level rejection as-is", async () => {
      const transportError = new TypeError("Failed to fetch");
      vi.mocked(fetch).mockRejectedValue(transportError);

      await expect(markItemDone(1)).rejects.toBe(transportError);
    });
  });
});
