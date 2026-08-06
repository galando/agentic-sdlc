import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import * as api from "../api";
import { ItemList } from "./ItemList";

vi.mock("../api");

describe("ItemList", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("renders items fetched on mount", async () => {
    vi.mocked(api.fetchItems).mockResolvedValue([
      { id: 1, title: "buy milk", done: false },
    ]);

    render(<ItemList />);

    expect(await screen.findByText("buy milk")).toBeInTheDocument();
  });

  it("adds a new item and shows it in the list", async () => {
    vi.mocked(api.fetchItems).mockResolvedValue([]);
    vi.mocked(api.createItem).mockResolvedValue({
      id: 2,
      title: "wash car",
      done: false,
    });
    const user = userEvent.setup();

    render(<ItemList />);
    await waitFor(() => expect(api.fetchItems).toHaveBeenCalled());

    await user.type(screen.getByLabelText("New item"), "wash car");
    await user.click(screen.getByRole("button", { name: "Add" }));

    expect(await screen.findByText("wash car")).toBeInTheDocument();
    expect(api.createItem).toHaveBeenCalledWith("wash car");
  });

  it("rejects a blank title without calling the API", async () => {
    vi.mocked(api.fetchItems).mockResolvedValue([]);
    const user = userEvent.setup();

    render(<ItemList />);
    await waitFor(() => expect(api.fetchItems).toHaveBeenCalled());

    await user.click(screen.getByRole("button", { name: "Add" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Title must not be blank.",
    );
    expect(api.createItem).not.toHaveBeenCalled();
  });

  it("marks an item done", async () => {
    vi.mocked(api.fetchItems).mockResolvedValue([
      { id: 3, title: "read book", done: false },
    ]);
    vi.mocked(api.markItemDone).mockResolvedValue({
      id: 3,
      title: "read book",
      done: true,
    });
    const user = userEvent.setup();

    render(<ItemList />);
    await user.click(await screen.findByRole("button", { name: "Mark done" }));

    expect(await screen.findByText("(done)")).toBeInTheDocument();
  });
});
