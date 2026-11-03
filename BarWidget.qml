import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A thin vertical rule that separates groups of chips in the bar.
//
// Right-clicking a divider adds another divider immediately after it. The
// copy is an ordinary layout entry of its own, so the bar's existing
// left-drag reordering moves each one independently; dragging it off the bar
// removes it. `allowMultiple` is true in the manifest.
//
// The duplicate is made by duplicate-divider.sh: the shell deliberately has no
// API for adding a second copy of a bar widget (`omarchy bar put` leaves one
// already on the bar alone, and a bar-widget plugin cannot write bar.layout).
// Each entry keeps a `dividerId` in its settings so the copy is placed beside
// the divider that was clicked, not merely at the section's end.
BarWidget {
  id: root
  moduleName: "io.github.nikhill-666.divider"

  readonly property bool opened: false

  function open() {}
  function close() {}
  function togglePanel() {}

  readonly property string dividerId: settings && settings.dividerId
    ? String(settings.dividerId) : ""
  readonly property string duplicateScript: String(Qt.resolvedUrl("duplicate-divider.sh"))
    .replace(/^file:\/\//, "")
  readonly property string hint: "Right-click to add another divider\n"
    + "Drag to move · Drag off the bar to remove"

  // Read by the bar's tooltip lookup; WidgetButton is not interactive here
  // because left-drag must stay with the bar's reordering handler.
  readonly property bool tooltipHovered: hoverArea.containsMouse
    && root.visible && root.opacity > 0

  function duplicate() {
    // argv, not a shell string: the id is only ever an argument.
    if (root.bar) root.bar.hideTooltip(root)
    Quickshell.execDetached(["bash", duplicateScript, moduleName, dividerId])
  }

  Component.onDestruction: if (root.bar) root.bar.hideTooltip(root)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    text: ""
    interactive: false
    pressable: false
    hasVisualContent: true
    keepSpace: true

    // The rule plus breathing room, so it does not crowd the chips either side.
    fixedWidth: Style.space(15)
    horizontalMargin: 0

    Rectangle {
      anchors.centerIn: parent
      width: Style.space(2)
      height: Math.round(Style.bar.sizeHorizontal * 0.62)
      radius: width / 2
      color: Color.muted
      opacity: hoverArea.containsMouse ? 0.9 : 0.55

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.ArrowCursor

    onEntered: if (root.bar) root.bar.showTooltip(root, root.hint)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: root.duplicate()
  }
}
