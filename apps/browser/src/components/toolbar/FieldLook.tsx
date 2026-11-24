import type { ComponentProps } from "react";
import { StyleSheet, View } from "react-native";
import { useSettings } from "../../state/browser/hooks";
import type { ToolbarRow } from "../../lib/toolbarRow";
import type { ToolbarPalette } from "../ui/toolbarColors";
import { useGlass } from "../ui/Glass";
import { ToolbarExtensions } from "../extensions/ToolbarExtensions";

export { FieldLoadFill } from "./FieldLoadFill";

export function useFieldChrome(palette: ToolbarPalette, hovered: boolean) {
  const glass = useGlass();
  const outlined = useSettings((s) => s.elementOutlines);
  const look = glass
    ? null
    : { backgroundColor: hovered ? palette.pressed : palette.hover, borderWidth: outlined ? 1 : StyleSheet.hairlineWidth, borderColor: palette.divider };
  return { glass, look };
}

type GroupedProps = ComponentProps<typeof ToolbarExtensions> & { row: ToolbarRow; groupRight: number; groupWidth: number };

export function GroupedToolbarExtensions({ row, groupRight, groupWidth, ...extensions }: GroupedProps) {
  return (
    <>
      {groupWidth > 0 ? (
        <View
          pointerEvents="none"
          style={{
            position: "absolute",
            top: row.center - row.field / 2,
            right: groupRight,
            width: groupWidth,
            height: row.field,
            borderRadius: row.fieldRadius,
            backgroundColor: extensions.palette.hover,
          }}
        />
      ) : null}
      <ToolbarExtensions {...extensions} />
    </>
  );
}
