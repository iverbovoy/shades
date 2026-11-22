import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Bar button plus the popup that drives the wallpaper service.
Panel {
  id: root
  moduleName: "verbovoy.shades"
  ipcTarget: "verbovoy.shades"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("verbovoy.shades") : null
  readonly property var config: service ? service.config : null

  // The colours the light can be given: the theme's own, the Omarchy accent,
  // and a few that suit a wall.
  readonly property var tints: ["", "accent", "#ffe2b0", "#ff9c5a", "#ff7a8a", "#b99cff", "#7fb4ff", "#7fe3d4"]

  readonly property string glyph: {
    if (!service || !config.enabled) return "\u{F0599}"   // sunny, idle
    if (service.day < 0.5) return "\u{F0594}"             // night
    if (service.overcastNow) return "\u{F0590}"           // cloudy
    return "\u{F0599}"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // which row has its list open, by its name; one at a time
  property string unrolled: ""
  onOpenedChanged: if (!opened) unrolled = ""

  // A setting that takes one of a few values. The arrows step back and
  // forth, and so do a click and a right click on the row. A row that is
  // given its `options` opens them as a list instead when it is clicked, for
  // where there are too many to step through: each is { key, label }, and
  // `current` is the key of the one in use.
  component StepRow: Item {
    id: row
    property string label: ""
    property string value: ""
    property var options: []
    property string current: ""
    signal stepped(int direction)
    signal picked(string key)

    readonly property bool listed: options.length > 0
    readonly property bool open: listed && root.unrolled === label
    readonly property int line: Style.spacing.popupRowHeight

    width: parent ? parent.width : 0
    height: line + (open ? list.height + Style.spacing.rowGap : 0)

    MouseArea {
      width: parent.width
      height: row.line
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) row.stepped(-1)
        else if (row.listed) root.unrolled = row.open ? "" : row.label
        else row.stepped(1)
      }
    }

    Text {
      id: stepLabel
      text: row.label
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      height: row.line
      verticalAlignment: Text.AlignVCenter
      anchors.left: parent.left
    }

    Arrow {
      id: back
      direction: -1
      height: row.line
      anchors.right: stepValue.left
      onClicked: row.stepped(-1)
    }

    Text {
      id: stepValue
      text: row.value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
      height: row.line
      verticalAlignment: Text.AlignVCenter
      // no wider than what the name and the arrows leave
      width: Math.min(implicitWidth, row.width - stepLabel.width - back.width - forth.width - Style.spacing.controlGap)
      anchors.right: forth.left
    }

    Arrow {
      id: forth
      direction: 1
      height: row.line
      anchors.right: parent.right
      onClicked: row.stepped(1)
    }

    // the list: seven at a time, the rest a turn of the wheel away
    ListView {
      id: list
      visible: row.open
      y: row.line + Style.spacing.rowGap
      width: parent.width
      height: Math.min(row.options.length, 7) * row.line
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: row.open ? row.options : []
      // opened on the one in use, once the list has been laid out
      function centre() {
        for (var i = 0; i < count; i++)
          if (row.options[i].key === row.current) { positionViewAtIndex(i, ListView.Center); break }
      }
      onCountChanged: if (count > 0) Qt.callLater(centre)

      delegate: Rectangle {
        id: option
        required property var modelData
        readonly property bool inUse: modelData.key === row.current

        width: list.width
        height: row.line
        radius: Style.cornerRadius
        color: optionMouse.containsMouse ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.10)
             : inUse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22) : "transparent"

        Text {
          text: option.modelData.label
          color: root.bar.foreground
          opacity: option.inUse ? 1 : 0.8
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: option.inUse
          elide: Text.ElideRight
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlGap
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlGap
          anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
          id: optionMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            row.picked(option.modelData.key)
            root.unrolled = ""
          }
        }
      }
    }
  }

  // One of the two arrows of such a row.
  component Arrow: Item {
    id: arrow
    property int direction: 1
    signal clicked()

    width: Style.space(22)

    Text {
      text: arrow.direction < 0 ? "\u2039" : "\u203A"
      color: root.bar.foreground
      opacity: arrowMouse.containsMouse ? 1 : 0.7
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      anchors.centerIn: parent
    }

    MouseArea {
      id: arrowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: arrow.clicked()
    }
  }

  // A setting that is a strength: a slider with its name and its value. The
  // setting itself is a multiple of what the theme and the sky make of it, and
  // a right click goes back to that; it is shown in per cent, or on whatever
  // scale `scale` and `unit` give it.
  component Dial: Item {
    id: dial
    property string label: ""
    property string key: ""
    property real minimum: 0
    property real maximum: 2
    property real scale: 100
    property string unit: "%"

    width: parent ? parent.width : 0
    height: Style.spacing.controlHeight

    Text {
      text: dial.label
      width: Style.space(40)
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    PanelSlider {
      id: slider
      bar: root.bar
      anchors.fill: parent
      anchors.leftMargin: Style.space(40) + Style.spacing.controlGap
      anchors.rightMargin: Style.space(40) + Style.spacing.controlGap
      minimum: dial.minimum
      maximum: dial.maximum
      step: 0.01
      value: root.config ? root.config[dial.key] : 1
      onMoved: function(v) { root.service.tune(dial.key, Math.round(v * 100) / 100) }
      onReleased: function(v) { root.service.tune(dial.key, Math.round(v * 100) / 100) }
      onRightClicked: root.service.tune(dial.key, 1)
    }

    Text {
      width: Style.space(40)
      horizontalAlignment: Text.AlignRight
      text: Math.round(dial.scale * (slider.dragging ? slider.liveValue : slider.value)) + dial.unit
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.service) root.service.set("enabled", !root.config.enabled)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.spacing.rowGap
        visible: root.service !== null

        // header: what the wall is doing right now, and the master switch
        Item {
          width: parent.width
          height: Math.max(title.implicitHeight + subtitle.implicitHeight + (notes.visible ? notes.implicitHeight : 0), Style.spacing.controlHeight)

          Text {
            id: title
            text: "Shades"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            id: subtitle
            anchors.top: title.bottom
            text: {
              if (!root.service) return ""
              var s = root.service
              var parts = []
              if (s.sun.sunrise && s.sun.sunset)
                parts.push(Qt.formatDateTime(s.sun.sunrise, "HH:mm") + " to " + Qt.formatDateTime(s.sun.sunset, "HH:mm"))
              if (s.weatherText) parts.push(s.weatherText)
              return parts.join("  ·  ")
            }
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          // what is changing the light just now and has no control here to
          // show it: said, so that a dim wall is no riddle
          Text {
            id: notes
            anchors.top: subtitle.bottom
            width: parent.width - Style.space(60)
            elide: Text.ElideRight
            visible: text !== ""
            text: {
              if (!root.service || !root.config) return ""
              var s = root.service, c = root.config
              var parts = []
              if (s.damaged) parts.push("settings file damaged: nothing is saved")
              if (s.yielded) parts.push("a video is playing: the wall has stepped aside")
              if (s.simHour >= 0) parts.push("previewing " + Qt.formatDateTime(s.now, "HH:mm"))
              if (c.overcast === "on") parts.push("overcast forced")
              else if (c.overcast === "off") parts.push("weather off")
              if (c.windowShadows) parts.push("window shadows")
              if (s.hushed) parts.push("blinds shut")
              else if (c.blindsFollow !== "none") parts.push("blinds by " + c.blindsFollow)
              return parts.join("  \u00B7  ")
            }
            color: Commons.Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          ToggleSwitch {
            checked: root.config ? root.config.enabled : false
            foreground: root.bar.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.service.set("enabled", !root.config.enabled)
          }
        }

        // how strong the light of the sun and the moon is, and how soft the
        // edges of what it casts
        Dial {
          label: "Light"
          key: "brightness"
          minimum: 0.2
          maximum: 4
          // on a scale of its own, 100 at the brightest
          scale: 25
          unit: ""
        }

        Dial {
          label: "Soft"
          key: "softness"
          minimum: 0.2
          maximum: 3
        }

        // how large the windows are
        Dial {
          label: "Size"
          key: "windowSize"
          minimum: 0.4
          maximum: 3
        }

        // and its colour: the first is the theme's own, the second the Omarchy accent
        Item {
          width: parent.width
          height: Style.spacing.popupRowHeight

          Text {
            text: "Colour"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            spacing: Style.spacing.controlGap
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: root.tints

              Rectangle {
                id: dot
                required property string modelData
                // a colour written into the file that is none of these picks none
                readonly property bool picked: root.config ? root.config.tint === modelData : false

                width: Style.space(18)
                height: width
                radius: width / 2
                // the theme's own is an empty ring
                color: modelData === "" ? "transparent" : modelData === "accent" ? Commons.Color.accent : modelData
                border.width: picked ? 2 : 1
                border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, picked ? 1 : 0.35)
                scale: picked ? 1.15 : 1

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.service.tune("tint", dot.modelData)
                }
              }
            }
          }
        }

        // Omarchy's own theme and the backgrounds it comes with: the wall is
        // lit on whichever is picked here, and the rest of the system follows
        StepRow {
          label: "Omarchy theme"
          value: {
            if (!root.service) return ""
            var s = root.service
            return s.titled(s.pendingTheme !== "" ? s.pendingTheme : s.systemTheme) + (s.pendingTheme !== "" ? "  \u2026" : "")
          }
          options: root.service ? root.service.systemThemes.map(function(t) { return { key: t, label: root.service.titled(t) } }) : []
          current: root.service ? (root.service.pendingTheme !== "" ? root.service.pendingTheme : root.service.systemTheme) : ""
          onStepped: function(direction) { root.service.stepSystemTheme(direction) }
          onPicked: function(key) { root.service.pickSystemTheme(key) }
        }

        StepRow {
          label: "Background"
          value: {
            if (!root.service) return ""
            var s = root.service
            return s.backgroundName + (s.backgrounds.length > 1 && s.backgroundIndex >= 0
              ? "  " + (s.backgroundIndex + 1) + "/" + s.backgrounds.length : "")
          }
          options: root.service ? root.service.backgrounds.map(function(b) { return { key: b, label: root.service.backgroundLabel(b) } }) : []
          current: root.service ? root.service.wallpaperPath : ""
          onStepped: function(direction) { root.service.stepBackground(direction) }
          onPicked: function(key) { root.service.pickBackground(key) }
        }

        StepRow {
          label: "Shades theme"
          value: root.service ? root.service.theme.label : ""
          options: root.service ? root.service.themeIds.map(function(t) { return { key: t, label: root.service.themeLabel(t) } }) : []
          current: root.config ? root.config.theme : ""
          onStepped: function(direction) { root.service.stepTheme(direction) }
          onPicked: function(key) { root.service.applyTheme(key) }
        }

        // how many windows stand in a row along the side wall
        StepRow {
          label: "Windows"
          value: root.service ? String(root.service.wantedCount) : ""
          onStepped: function(direction) { root.service.stepWindows(direction) }
        }

        // the room itself on the move: a lift, a train, a ship, a racing car
        StepRow {
          label: "Motion"
          value: root.service && root.service.moving ? root.service.motion : "still"
          onStepped: function(direction) { root.service.stepMotion(direction) }
        }

        // the shell's bar over the wall: solid, clear or tinted
        StepRow {
          label: "Bar"
          value: root.config && root.config.bar !== "" ? root.config.bar : "solid"
          onStepped: function(direction) { root.service.stepBar(direction) }
        }
      }
    }
  }
}
