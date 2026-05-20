import { Compartment, EditorState, type Extension } from "@codemirror/state";
import {
  EditorView,
  type Panel,
  drawSelection,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import {
  SearchQuery,
  closeSearchPanel,
  findNext,
  findPrevious,
  getSearchQuery,
  search,
  searchKeymap,
  setSearchQuery,
} from "@codemirror/search";
import { StreamLanguage } from "@codemirror/language";
import { javascript } from "@codemirror/lang-javascript";
import { python } from "@codemirror/lang-python";
import { rust } from "@codemirror/lang-rust";
import { json } from "@codemirror/lang-json";
import { markdown } from "@codemirror/lang-markdown";
import { html } from "@codemirror/lang-html";
import { css } from "@codemirror/lang-css";
import { sql } from "@codemirror/lang-sql";
import { yaml } from "@codemirror/lang-yaml";
import { xml } from "@codemirror/lang-xml";
import { cpp } from "@codemirror/lang-cpp";
import { go } from "@codemirror/lang-go";
import { java } from "@codemirror/lang-java";
import { php } from "@codemirror/lang-php";
import { swift } from "@codemirror/legacy-modes/mode/swift";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { toml } from "@codemirror/legacy-modes/mode/toml";
import { ruby } from "@codemirror/legacy-modes/mode/ruby";
import { lua } from "@codemirror/legacy-modes/mode/lua";
import { oneDark } from "@codemirror/theme-one-dark";
import { MergeView } from "@codemirror/merge";

type ThemePalette = {
  background: string;
  foreground: string;
  gutterBackground: string;
  gutterForeground: string;
  selectionBackground: string;
  activeLineBackground: string;
};

type Payload = {
  content?: string;
  language?: string;
  isDark?: boolean;
  fontSize?: number;
  readOnly?: boolean;
  diffOriginal?: string;
  diffModified?: string;
  theme?: ThemePalette;
};

type SwiftHandler = {
  postMessage: (msg: { action: string; [k: string]: unknown }) => void;
};

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        cmuxCode?: SwiftHandler;
      };
    };
  }
}

function postToSwift(action: string, extra: Record<string, unknown> = {}) {
  const handler = window.webkit?.messageHandlers?.cmuxCode;
  if (!handler) return;
  try {
    handler.postMessage({ action, ...extra });
  } catch {
    // No-op: WebKit may have torn down the bridge.
  }
}

const fontSizeCompartment = new Compartment();
const themeCompartment = new Compartment();
const languageCompartment = new Compartment();
const readOnlyCompartment = new Compartment();

function languageExtension(id: string | undefined): Extension {
  switch (id) {
    case "typescript":
    case "tsx":
      return javascript({ typescript: true, jsx: true });
    case "javascript":
    case "jsx":
      return javascript({ jsx: true });
    case "python":
      return python();
    case "rust":
      return rust();
    case "json":
      return json();
    case "markdown":
      return markdown();
    case "html":
      return html();
    case "css":
      return css();
    case "sql":
      return sql();
    case "yaml":
      return yaml();
    case "xml":
      return xml();
    case "cpp":
    case "c":
      return cpp();
    case "go":
      return go();
    case "java":
      return java();
    case "php":
      return php();
    case "swift":
      return StreamLanguage.define(swift);
    case "shell":
    case "bash":
      return StreamLanguage.define(shell);
    case "toml":
      return StreamLanguage.define(toml);
    case "ruby":
      return StreamLanguage.define(ruby);
    case "lua":
      return StreamLanguage.define(lua);
    default:
      return [];
  }
}

let contentChangeTimer: number | null = null;
function scheduleContentChange(view: EditorView) {
  if (contentChangeTimer != null) {
    window.clearTimeout(contentChangeTimer);
  }
  contentChangeTimer = window.setTimeout(() => {
    contentChangeTimer = null;
    postToSwift("contentChanged", { content: view.state.doc.toString() });
  }, 120);
}

const contentChangeListener = EditorView.updateListener.of((u) => {
  if (u.docChanged) scheduleContentChange(u.view);
});

// A minimal find widget modeled on VS Code's: a compact bar attached to the
// top-right edge, with the case / whole-word / regex toggles tucked inside
// the input and small icon buttons for previous / next / close.
function createSearchPanel(view: EditorView): Panel {
  const initial = getSearchQuery(view.state);
  let caseSensitive = initial.caseSensitive;
  let wholeWord = initial.wholeWord;
  let regexp = initial.regexp;

  const dom = document.createElement("div");
  dom.className = "cmux-search";
  dom.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      e.preventDefault();
      closeSearchPanel(view);
      view.focus();
    }
  });

  const field = document.createElement("input");
  field.className = "cmux-search-input";
  field.placeholder = "Find";
  field.spellcheck = false;
  field.setAttribute("aria-label", "Find");
  field.setAttribute("main-field", "true");
  field.value = initial.search;

  const makeButton = (cls: string, label: string, title: string) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = cls;
    button.textContent = label;
    button.title = title;
    button.setAttribute("aria-label", title);
    button.tabIndex = -1;
    return button;
  };

  const caseButton = makeButton("cmux-search-toggle", "Aa", "Match Case");
  const wordButton = makeButton("cmux-search-toggle", "ab", "Match Whole Word");
  const regexpButton = makeButton("cmux-search-toggle", ".*", "Use Regular Expression");
  const prevButton = makeButton("cmux-search-action", "↑", "Previous Match");
  const nextButton = makeButton("cmux-search-action", "↓", "Next Match");
  const closeButton = makeButton("cmux-search-action", "✕", "Close");

  const syncToggles = () => {
    caseButton.classList.toggle("cmux-search-toggle-on", caseSensitive);
    wordButton.classList.toggle("cmux-search-toggle-on", wholeWord);
    regexpButton.classList.toggle("cmux-search-toggle-on", regexp);
  };
  syncToggles();

  const commitQuery = () => {
    view.dispatch({
      effects: setSearchQuery.of(
        new SearchQuery({
          search: field.value,
          caseSensitive,
          regexp,
          wholeWord,
        })
      ),
    });
  };

  field.addEventListener("input", commitQuery);
  field.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      if (e.shiftKey) findPrevious(view);
      else findNext(view);
    }
  });

  const toggle = (button: HTMLButtonElement, apply: () => void) => {
    button.addEventListener("click", () => {
      apply();
      syncToggles();
      commitQuery();
      field.focus();
    });
  };
  toggle(caseButton, () => {
    caseSensitive = !caseSensitive;
  });
  toggle(wordButton, () => {
    wholeWord = !wholeWord;
  });
  toggle(regexpButton, () => {
    regexp = !regexp;
  });
  prevButton.addEventListener("click", () => {
    findPrevious(view);
    field.focus();
  });
  nextButton.addEventListener("click", () => {
    findNext(view);
    field.focus();
  });
  closeButton.addEventListener("click", () => {
    closeSearchPanel(view);
    view.focus();
  });

  const toggles = document.createElement("div");
  toggles.className = "cmux-search-toggles";
  toggles.append(caseButton, wordButton, regexpButton);

  const fieldWrap = document.createElement("div");
  fieldWrap.className = "cmux-search-field";
  fieldWrap.append(field, toggles);

  dom.append(fieldWrap, prevButton, nextButton, closeButton);

  return {
    dom,
    top: true,
    mount() {
      if (field.value && field.value !== getSearchQuery(view.state).search) {
        commitQuery();
      }
      field.focus();
      field.select();
    },
  };
}

// Colors are driven by CSS variables set in `setPanelVars` so the widget
// tracks the active theme.
function searchPanelTheme(): Extension {
  return EditorView.theme({
    ".cm-panels.cm-panels-top": {
      position: "absolute",
      top: "0",
      right: "14px",
      left: "auto",
      width: "auto",
      backgroundColor: "transparent",
      border: "none",
      zIndex: "20",
    },
    ".cmux-search": {
      display: "flex",
      alignItems: "center",
      gap: "1px",
      padding: "3px 4px",
      borderRadius: "0 0 4px 4px",
      backgroundColor: "var(--cmux-panel-bg)",
      border: "1px solid var(--cmux-panel-border)",
      borderTop: "none",
      boxShadow: "0 2px 8px rgba(0, 0, 0, 0.3)",
      color: "var(--cmux-panel-fg)",
      fontFamily: "ui-sans-serif, system-ui, -apple-system, sans-serif",
    },
    ".cmux-search-field": {
      position: "relative",
      display: "flex",
      alignItems: "center",
      marginRight: "3px",
    },
    ".cmux-search-input": {
      width: "170px",
      height: "22px",
      boxSizing: "border-box",
      padding: "0 70px 0 6px",
      fontSize: "12px",
      color: "var(--cmux-panel-fg)",
      backgroundColor: "var(--cmux-panel-input-bg)",
      border: "1px solid transparent",
      borderRadius: "2px",
      outline: "none",
    },
    ".cmux-search-input:focus": {
      borderColor: "var(--cmux-panel-accent)",
    },
    ".cmux-search-input::placeholder": {
      color: "var(--cmux-panel-fg)",
      opacity: "0.45",
    },
    ".cmux-search-toggles": {
      position: "absolute",
      right: "2px",
      display: "flex",
      gap: "1px",
    },
    ".cmux-search-toggle": {
      width: "20px",
      height: "18px",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      padding: "0",
      fontSize: "10px",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      color: "var(--cmux-panel-fg)",
      backgroundColor: "transparent",
      border: "1px solid transparent",
      borderRadius: "3px",
      cursor: "pointer",
    },
    ".cmux-search-toggle:hover": {
      backgroundColor: "var(--cmux-panel-hover)",
    },
    ".cmux-search-toggle-on": {
      backgroundColor: "var(--cmux-panel-toggle-on-bg)",
      borderColor: "var(--cmux-panel-accent)",
    },
    ".cmux-search-action": {
      width: "22px",
      height: "22px",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      padding: "0",
      fontSize: "12px",
      lineHeight: "1",
      color: "var(--cmux-panel-fg)",
      backgroundColor: "transparent",
      border: "none",
      borderRadius: "3px",
      cursor: "pointer",
    },
    ".cmux-search-action:hover": {
      backgroundColor: "var(--cmux-panel-hover)",
    },
  });
}

function baseExtensions(): Extension[] {
  return [
    lineNumbers(),
    highlightActiveLine(),
    highlightActiveLineGutter(),
    drawSelection(),
    EditorState.allowMultipleSelections.of(true),
    history(),
    search({ top: true, createPanel: createSearchPanel }),
    searchPanelTheme(),
    // Save chord is intercepted on the Swift side so it can honor the user's
    // KeyboardShortcutSettings.saveFilePreview binding (which may be a chord
    // like ⌘K ⌘S). The bridge still exposes a `requestSave` action for any
    // future JS-triggered save flows (e.g. an in-editor "Save" button).
    keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap]),
    fontSizeCompartment.of(EditorView.theme({ "&": { fontSize: "13px" } })),
    themeCompartment.of([]),
    languageCompartment.of([]),
    readOnlyCompartment.of(EditorState.readOnly.of(false)),
    contentChangeListener,
  ];
}

let editor: EditorView | null = null;
let mergeView: MergeView | null = null;

function teardown() {
  if (mergeView) {
    mergeView.destroy();
    mergeView = null;
  }
  if (editor) {
    editor.destroy();
    editor = null;
  }
}

function mountSingle(parent: HTMLElement, content: string) {
  teardown();
  editor = new EditorView({
    parent,
    state: EditorState.create({ doc: content, extensions: baseExtensions() }),
  });
}

function mountDiff(parent: HTMLElement, original: string, modified: string) {
  teardown();
  mergeView = new MergeView({
    parent,
    a: { doc: original, extensions: baseExtensions() },
    b: { doc: modified, extensions: baseExtensions() },
    revertControls: "b-to-a",
    highlightChanges: true,
    gutter: true,
  });
}

function applyLanguage(id: string | undefined) {
  const ext = languageExtension(id);
  const effects = languageCompartment.reconfigure(ext);
  editor?.dispatch({ effects });
  mergeView?.a.dispatch({ effects });
  mergeView?.b.dispatch({ effects });
}

function paletteTheme(palette: ThemePalette): Extension {
  return EditorView.theme(
    {
      "&": {
        color: palette.foreground,
        backgroundColor: palette.background,
      },
      ".cm-content": { caretColor: palette.foreground },
      ".cm-gutters": {
        backgroundColor: palette.gutterBackground,
        color: palette.gutterForeground,
        border: "none",
      },
      ".cm-activeLine": { backgroundColor: palette.activeLineBackground },
      ".cm-activeLineGutter": { backgroundColor: palette.activeLineBackground },
      "&.cm-focused .cm-selectionBackground, ::selection": {
        backgroundColor: palette.selectionBackground,
      },
    },
    { dark: false }
  );
}

// Drive the find widget's colors. The widget styling in `searchPanelTheme`
// is static, so theme changes flow through CSS variables set here instead
// of reconfiguring a compartment.
function setPanelVars(isDark: boolean, palette?: ThemePalette) {
  const root = document.documentElement.style;
  root.setProperty("--cmux-panel-bg", palette?.background ?? (isDark ? "#252526" : "#ffffff"));
  root.setProperty("--cmux-panel-fg", palette?.foreground ?? (isDark ? "#cccccc" : "#1f1f1f"));
  root.setProperty(
    "--cmux-panel-border",
    isDark ? "rgba(255, 255, 255, 0.14)" : "rgba(0, 0, 0, 0.14)"
  );
  root.setProperty(
    "--cmux-panel-input-bg",
    isDark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.04)"
  );
  root.setProperty(
    "--cmux-panel-hover",
    isDark ? "rgba(255, 255, 255, 0.10)" : "rgba(0, 0, 0, 0.07)"
  );
  root.setProperty(
    "--cmux-panel-toggle-on-bg",
    isDark ? "rgba(10, 132, 255, 0.38)" : "rgba(10, 132, 255, 0.20)"
  );
  root.setProperty("--cmux-panel-accent", "#0a84ff");
}

function applyTheme(isDark: boolean, palette?: ThemePalette) {
  const base = isDark ? oneDark : [];
  const overlay = palette ? paletteTheme(palette) : [];
  const effects = themeCompartment.reconfigure([base, overlay]);
  editor?.dispatch({ effects });
  mergeView?.a.dispatch({ effects });
  mergeView?.b.dispatch({ effects });
  document.documentElement.style.colorScheme = isDark ? "dark" : "light";
  document.body.style.background = palette?.background ?? "transparent";
  setPanelVars(isDark, palette);
}

function applyReadOnly(readOnly: boolean) {
  const effects = readOnlyCompartment.reconfigure(EditorState.readOnly.of(readOnly));
  editor?.dispatch({ effects });
  mergeView?.a.dispatch({ effects });
  mergeView?.b.dispatch({ effects });
}

function applyFontSize(px: number) {
  const ext = EditorView.theme({ "&": { fontSize: `${px}px` } });
  const effects = fontSizeCompartment.reconfigure(ext);
  editor?.dispatch({ effects });
  mergeView?.a.dispatch({ effects });
  mergeView?.b.dispatch({ effects });
}

function ensureRoot(): HTMLElement {
  let root = document.getElementById("editor");
  if (!root) {
    root = document.createElement("div");
    root.id = "editor";
    document.body.appendChild(root);
  }
  return root;
}

declare global {
  interface Window {
    __cmuxCodeApply?: (payload: Payload | string) => void;
    __cmuxCodeGet?: () => string;
    __cmuxCodeSetFontSize?: (px: number) => void;
  }
}

window.__cmuxCodeApply = function (payload) {
  const root = ensureRoot();
  const p: Payload = typeof payload === "string" ? JSON.parse(payload) : payload;
  if (p.diffOriginal != null && p.diffModified != null) {
    mountDiff(root, p.diffOriginal, p.diffModified);
  } else {
    mountSingle(root, p.content ?? "");
  }
  applyLanguage(p.language);
  applyTheme(!!p.isDark, p.theme);
  applyFontSize(p.fontSize ?? 13);
  applyReadOnly(!!p.readOnly);
};

window.__cmuxCodeGet = function () {
  if (editor) return editor.state.doc.toString();
  if (mergeView) return mergeView.b.state.doc.toString();
  return "";
};

window.__cmuxCodeSetFontSize = function (px) {
  applyFontSize(px);
};

document.documentElement.dataset.cmuxCodeViewerReady = "1";
postToSwift("ready");
