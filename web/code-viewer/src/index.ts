import { Compartment, EditorState, type Extension } from "@codemirror/state";
import {
  EditorView,
  drawSelection,
  highlightActiveLine,
  highlightActiveLineGutter,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { search, searchKeymap } from "@codemirror/search";
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

function baseExtensions(): Extension[] {
  return [
    lineNumbers(),
    highlightActiveLine(),
    highlightActiveLineGutter(),
    drawSelection(),
    EditorState.allowMultipleSelections.of(true),
    history(),
    search({ top: true }),
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

function applyTheme(isDark: boolean, palette?: ThemePalette) {
  const base = isDark ? oneDark : [];
  const overlay = palette ? paletteTheme(palette) : [];
  const effects = themeCompartment.reconfigure([base, overlay]);
  editor?.dispatch({ effects });
  mergeView?.a.dispatch({ effects });
  mergeView?.b.dispatch({ effects });
  document.documentElement.style.colorScheme = isDark ? "dark" : "light";
  document.body.style.background = palette?.background ?? "transparent";
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
