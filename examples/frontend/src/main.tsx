import React from "react";
import ReactDOM from "react-dom/client";
import { ItemList } from "./components/ItemList";
import "./tokens.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ItemList />
  </React.StrictMode>,
);
