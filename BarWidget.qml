import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A vertical mark that separates groups of chips in the bar.
//
// Right-clicking a divider opens a small style menu: a row of shape swatches
// (line, dot, oval, square, rounded square), width and height sliders, a colour
// row, and a "Duplicate divider" action. Each divider keeps its own style in
// its layout entry, so a row can mix them, and duplicating a divider copies its
// style.
//
// Nothing is written while the menu is open: the mark updates from local state
// so sliders feel live, and the whole style is saved once when the menu closes.
// A duplicate made from the menu carries the on-screen style with it, so the
// new divider looks like its parent without waiting for a save.
//
// The copy is an ordinary layout entry of its own, so the bar's existing
// left-drag reordering moves each one independently; dragging it off the bar
// removes it. `allowMultiple` is true in the manifest.
//
// duplicate-divider.sh and set-divider-style.sh do the writing: the shell
// deliberately has no API for adding a second copy of a bar widget (`omarchy
// bar put` leaves one already on the bar alone, and a bar-widget plugin cannot
// write bar.layout). Each entry keeps a `dividerId` in its settings so the copy
// is placed beside the divider that was clicked, not merely at the section's
// end. The shell's updateEntryInline cannot save the style instead: for an
// allowMultiple widget it rewrites every entry, which would give all dividers
// one style (and one dividerId).
BarWidget {
  id: root
  moduleName: "io.github.nikhill-666.divider"

  // Shapes offered by the style menu, and the size each starts from as a
  // percentage of the bar height. The line is the original 2px rule at 62%.
  readonly property var shapeNames: ["line", "dot", "oval", "square", "rounded"]
  readonly property var shapeDefaults: ({
    line:    { w: 8,  h: 62 },
    dot:     { w: 22, h: 22 },
    oval:    { w: 22, h: 50 },
    square:  { w: 22, h: 22 },
    rounded: { w: 22, h: 22 }
  })
  readonly property var colourRoles: ["theme", "accent", "foreground", "urgent"]
  readonly property int minWidth: 2
  readonly property int maxWidth: 30
  readonly property int minHeight: 6
  readonly property int maxHeight: 100
  // Menu geometry: the label column, and the four colour swatches plus gaps.
  readonly property int labelWidth: Style.space(42)
  readonly property int swatchesWidth: root.colourRoles.length * Style.space(20)
    + (root.colourRoles.length - 1) * Style.spacing.xs

  property bool menuOpen: false

  // Panel shape contract read by the bar (open/close/opened). The style menu
  // is a per-instance PopupCard rather than a shell panel, so summoning this
  // widget just opens its menu.
  readonly property bool opened: menuOpen

  function open() { menuOpen = true }
  function close() { menuOpen = false }
  function togglePanel() { menuOpen = !menuOpen }

  readonly property string dividerId: settings && settings.dividerId
    ? String(settings.dividerId) : ""
  readonly property string duplicateScript: String(Qt.resolvedUrl("duplicate-divider.sh"))
    .replace(/^file:\/\//, "")
  readonly property string styleScript: String(Qt.resolvedUrl("set-divider-style.sh"))
    .replace(/^file:\/\//, "")
  readonly property string hint: "Right-click to style or duplicate\n"
    + "Drag to move · Drag off the bar to remove"

  // Read by the bar's tooltip lookup; WidgetButton is not interactive here
  // because left-drag must stay with the bar's reordering handler.
  readonly property bool tooltipHovered: hoverArea.containsMouse
    && !root.menuOpen && root.visible && root.opacity > 0

  // The style painted right now. Local so the menu previews it immediately;
  // the layout entry is the source of truth and is written when the menu closes.
  property string shape: "line"
  property int widthPct: 8
  property int heightPct: 62
  property string colour: "theme"
  // What was last seen in settings or sent to the scripts, so closing an
  // untouched menu writes nothing.
  property string savedStyle: ""

  function clampInt(value, min, max, fallback) {
    var n = Number(value)
    if (!isFinite(n)) n = fallback
    n = Math.round(n)
    return n < min ? min : n > max ? max : n
  }

  function normaliseShape(value) {
    var candidate = String(value || "")
    return root.shapeNames.indexOf(candidate) === -1 ? "line" : candidate
  }

  function normaliseColour(value) {
    var candidate = String(value || "").toLowerCase()
    if (root.colourRoles.indexOf(candidate) !== -1) return candidate
    return /^#[0-9a-f]{6}$/.test(candidate) ? candidate : "theme"
  }

  function loadStyle() {
    var next = root.normaliseShape(root.setting("shape", "line"))
    var defaults = root.shapeDefaults[next]
    root.shape = next
    root.widthPct = root.clampInt(root.setting("width", defaults.w),
                                  root.minWidth, root.maxWidth, defaults.w)
    root.heightPct = root.clampInt(root.setting("height", defaults.h),
                                   root.minHeight, root.maxHeight, defaults.h)
    root.colour = root.normaliseColour(root.setting("color", "theme"))
    root.syncColourField()
    root.savedStyle = root.styleJson()
  }

  // The field is the only control that can hold an uncommitted edit, so it is
  // not bound to `colour`: a half-typed value must survive a render.
  function syncColourField() {
    colourField.text = root.colour.charAt(0) === "#" ? root.colour : ""
  }

  Component.onCompleted: root.loadStyle()
  // An open menu owns the style; a reload underneath it must not yank a slider
  // out from under the pointer.
  onSettingsChanged: if (!root.menuOpen) root.loadStyle()

  function styleJson() {
    return JSON.stringify({
      shape: root.shape,
      width: root.widthPct,
      height: root.heightPct,
      color: root.colour
    })
  }

  // One write for the whole session with the menu, rather than one per slider
  // step: the shell rebuilds a widget whose entry changed.
  function flush() {
    // Clicking the bar to dismiss the menu must not throw away a typed hex.
    root.commitColour(colourField.text)
    var payload = root.styleJson()
    if (payload === root.savedStyle) return
    root.savedStyle = payload
    Quickshell.execDetached(["bash", root.styleScript, root.moduleName, root.dividerId, payload])
  }

  onMenuOpenChanged: if (!root.menuOpen) root.flush()

  // Choosing a shape resets the size to that shape's natural one, unless the
  // size has already been tuned — then the tuning is what the user wants.
  function chooseShape(name) {
    var next = root.normaliseShape(name)
    if (next === root.shape) return
    var previous = root.shapeDefaults[root.shape]
    var untouched = root.widthPct === previous.w && root.heightPct === previous.h
    root.shape = next
    if (untouched) {
      var defaults = root.shapeDefaults[next]
      root.widthPct = defaults.w
      root.heightPct = defaults.h
    }
  }

  function chooseColour(role) {
    root.colour = root.normaliseColour(role)
    root.syncColourField()
  }

  // Accept #abc or abc as well as #aabbcc, and put the field back to the
  // current value when the text is not a colour at all.
  function commitColour(text) {
    var raw = String(text || "").trim().toLowerCase()
    if (raw === "") {
      root.syncColourField()
      return
    }
    if (raw.charAt(0) !== "#") raw = "#" + raw
    if (/^#[0-9a-f]{3}$/.test(raw)) {
      raw = "#" + raw.charAt(1) + raw.charAt(1) + raw.charAt(2) + raw.charAt(2)
        + raw.charAt(3) + raw.charAt(3)
    }
    if (!/^#[0-9a-f]{6}$/.test(raw)) {
      root.syncColourField()
      return
    }
    root.colour = raw
    root.syncColourField()
  }

  function colourFor(role) {
    switch (root.normaliseColour(role)) {
    case "accent": return Color.accent
    case "foreground": return root.bar ? root.bar.barForeground : Color.foreground
    case "urgent": return root.bar ? root.bar.urgent : Color.urgent
    }
    return Color.muted
  }

  readonly property color markColour: {
    var role = root.normaliseColour(root.colour)
    return role.charAt(0) === "#" ? role : root.colourFor(role)
  }

  // Corner treatment is the shape's real identity: line, dot and oval are all
  // fully rounded and differ by their starting size; square is hard; rounded is
  // softened. A user who stretches a dot into a capsule gets a capsule.
  function radiusFor(name, w, h) {
    var shortSide = Math.min(w, h)
    switch (root.normaliseShape(name)) {
    case "square": return 0
    case "rounded": return Math.max(1, Math.round(shortSide * 0.28))
    }
    return Math.round(shortSide / 2)
  }

  // The mark the bar shows, at the current size.
  readonly property var mark: {
    var bar = Math.max(1, root.barSize)
    var w = Math.max(1, Math.round(bar * root.widthPct / 100))
    var h = Math.max(1, Math.round(bar * root.heightPct / 100))
    return { w: w, h: h, r: root.radiusFor(root.shape, w, h) }
  }

  // A shape's natural look, enlarged to fit a menu cell. Previews deliberately
  // ignore the current size so the five options stay distinguishable.
  function previewFor(name) {
    var defaults = root.shapeDefaults[root.normaliseShape(name)]
    var bar = Math.max(1, root.barSize)
    var scale = 1.7
    var w = Math.max(1, Math.round(bar * defaults.w / 100 * scale))
    var h = Math.max(1, Math.round(bar * defaults.h / 100 * scale))
    var cap = Style.space(32)
    if (w > cap || h > cap) {
      var fit = cap / Math.max(w, h)
      w = Math.max(1, Math.round(w * fit))
      h = Math.max(1, Math.round(h * fit))
    }
    return { w: w, h: h, r: root.radiusFor(name, w, h) }
  }

  function duplicate() {
    if (root.bar) root.bar.hideTooltip(root)
    // The duplicate script merges this into the entry before cloning it, so
    // the copy matches what the menu is showing without a separate save.
    root.commitColour(colourField.text)
    var payload = root.styleJson()
    root.savedStyle = payload
    root.menuOpen = false
    Quickshell.execDetached(["bash", root.duplicateScript, moduleName, dividerId, payload])
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

    // The mark plus breathing room, so it does not crowd the chips either
    // side. A wide mark widens its slot instead of painting over its
    // neighbour; on a vertical bar it is the slot's length that grows.
    fixedWidth: root.vertical ? root.barSize
      : Math.max(Style.space(15), root.mark.w + Style.space(6))
    fixedHeight: root.vertical
      ? Math.max(Style.space(15), root.mark.w + Style.space(6)) : -1
    horizontalMargin: 0

    Rectangle {
      anchors.centerIn: parent

      // A vertical bar draws the same marks turned on their side.
      width: root.vertical ? root.mark.h : root.mark.w
      height: root.vertical ? root.mark.w : root.mark.h
      radius: root.mark.r
      color: root.markColour
      opacity: hoverArea.containsMouse || root.menuOpen ? 0.9 : 0.55

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
    onClicked: {
      if (root.bar) root.bar.hideTooltip(root)
      root.menuOpen = !root.menuOpen
    }
  }

  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(262))
    contentHeight: menu.fittedContentHeight(column.implicitHeight)
    onOpenChanged: if (!open) root.menuOpen = false

    Column {
      id: column
      width: parent.width
      spacing: Style.spacing.sm

      Shortcut {
        enabled: root.menuOpen
        sequence: "Escape"
        onActivated: root.close()
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Divider shape"
        color: Color.popups.text
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        id: shapeRow
        width: parent.width
        spacing: Style.spacing.xs

        Repeater {
          model: root.shapeNames

          delegate: Item {
            id: cell
            required property string modelData

            readonly property bool current: root.shape === modelData
            readonly property bool hot: cellHover.hovered

            width: Math.floor((shapeRow.width - shapeRow.spacing * (root.shapeNames.length - 1))
                              / root.shapeNames.length)
            height: Style.space(36)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: cell.current ? Util.alpha(Color.accent, 0.16)
                : cell.hot ? Util.alpha(Color.foreground, 0.08)
                : "transparent"
              border.width: cell.current ? Style.normalBorderWidth : 0
              border.color: Util.alpha(Color.accent, 0.6)
            }

            Rectangle {
              anchors.centerIn: parent

              readonly property var spec: root.previewFor(cell.modelData)

              width: spec.w
              height: spec.h
              radius: spec.r
              color: root.markColour
              opacity: cell.current || cell.hot ? 1 : 0.75
            }

            HoverHandler {
              id: cellHover
              cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
              onTapped: root.chooseShape(cell.modelData)
            }
          }
        }
      }

      // Width and height, as a percentage of the bar height so the mark keeps
      // its proportions when the bar changes.
      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: root.labelWidth
          height: widthSlider.implicitHeight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: "Width"
          color: Color.popups.text
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          id: widthSlider
          width: column.width - root.labelWidth - widthValue.width - Style.spacing.sm * 2
          bar: root.bar
          minimum: root.minWidth
          maximum: root.maxWidth
          step: 1
          integer: true
          value: root.widthPct
          onMoved: function (v) { root.widthPct = Math.round(v) }
        }

        Text {
          id: widthValue
          width: Style.space(30)
          height: widthSlider.implicitHeight
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.widthPct + "%"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: root.labelWidth
          height: heightSlider.implicitHeight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: "Height"
          color: Color.popups.text
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSlider {
          id: heightSlider
          width: column.width - root.labelWidth - heightValue.width - Style.spacing.sm * 2
          bar: root.bar
          minimum: root.minHeight
          maximum: root.maxHeight
          step: 1
          integer: true
          value: root.heightPct
          onMoved: function (v) { root.heightPct = Math.round(v) }
        }

        Text {
          id: heightValue
          width: Style.space(30)
          height: heightSlider.implicitHeight
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.heightPct + "%"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          width: root.labelWidth
          height: Style.spacing.controlHeight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: "Colour"
          color: Color.popups.text
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          id: colourRow
          spacing: Style.spacing.xs

          Repeater {
            model: root.colourRoles

            delegate: Item {
              id: swatch
              required property string modelData

              readonly property bool current: root.colour === modelData

              width: Style.space(20)
              height: Style.space(20)

              Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.colourFor(swatch.modelData)
                border.width: swatch.current ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth)
                border.color: swatch.current ? Color.popups.text : Util.alpha(Color.popups.text, 0.25)
              }

              HoverHandler {
                id: swatchHover
                cursorShape: Qt.PointingHandCursor
              }

              TapHandler {
                onTapped: root.chooseColour(swatch.modelData)
              }
            }
          }
        }

        TextField {
          id: colourField
          width: Math.max(Style.space(48),
                          column.width - root.labelWidth - root.swatchesWidth - Style.spacing.sm * 2)
          height: Style.spacing.controlHeight
          verticalAlignment: TextInput.AlignVCenter
          placeholderText: "#rrggbb"
          foreground: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalPadding: Style.space(4)
          onAccepted: root.commitColour(text)
          onEditingFinished: root.commitColour(text)
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(Color.foreground, 0.12)
      }

      Button {
        width: parent.width
        leftAlign: true
        text: "Duplicate divider"
        onClicked: root.duplicate()
      }
    }
  }
}
