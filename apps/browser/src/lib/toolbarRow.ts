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
  compact: { height: 34, center: 17, button: 26, buttonRadius: 7, field: 28, fieldRadius: 8, fieldButton: 22, fieldButtonRadius: 6, extensionButton: 24 },
};

export const toolbarRowOf = (compact: boolean): ToolbarRow => (compact ? TOOLBAR_ROWS.compact : TOOLBAR_ROWS.regular);

export const urlFieldOf = (row: ToolbarRow) => ({ top: row.center - row.field / 2, height: row.field });

export const compactLift = (row: ToolbarRow) => Math.round((TOOLBAR_ROWS.regular.center - row.center) * 2) / 2;
