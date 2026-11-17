export type ToolbarRow = {
  height: number;
  center: number;
  button: number;
  buttonRadius: number;
  field: number;
  fieldRadius: number;
  fieldButton: number;
  fieldButtonRadius: number;
  extensionButton: number;
};

export const TOOLBAR_ROWS: Record<"regular" | "compact", ToolbarRow> = {
  regular: { height: 44, center: 22, button: 30, buttonRadius: 8, field: 34, fieldRadius: 10, fieldButton: 26, fieldButtonRadius: 7, extensionButton: 28 },
  compact: { height: 38, center: 19, button: 28, buttonRadius: 7, field: 30, fieldRadius: 9, fieldButton: 24, fieldButtonRadius: 6, extensionButton: 26 },
};

export const toolbarRowOf = (compact: boolean): ToolbarRow => (compact ? TOOLBAR_ROWS.compact : TOOLBAR_ROWS.regular);

export const urlFieldOf = (row: ToolbarRow) => ({ top: row.center - row.field / 2, height: row.field });

export const compactLift = (row: ToolbarRow) => Math.round((TOOLBAR_ROWS.regular.center - row.center) * 2) / 2;
