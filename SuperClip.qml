import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  property var texts: []
  property var images: []
  property var screenshots: []
  property var screenshotHashes: ({})
  property var imageHashes: ({})
  property string textFilter: ""
  property string favFilter: ""
  property string hoverPreviewPath: ""

  readonly property var filteredTexts: {
    var q = root.textFilter.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.texts.length; i++) {
      var e = root.texts[i]
      if (!q || String(e.text || "").toLowerCase().indexOf(q) >= 0) out.push(e)
    }
    return out
  }

  readonly property var filteredResponses: {
    var q = root.favFilter.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.responses.length; i++) {
      var r = root.responses[i]
      var hay = String(r.label || "") + " " + String(r.text || "")
      if (!q || hay.toLowerCase().indexOf(q) >= 0) out.push(r)
    }
    return out
  }

  function textOriginalIndex(i) {
    var t = root.filteredTexts[i]
    return root.texts.indexOf(t)
  }

  function responseOriginalIndex(i) {
    var r = root.filteredResponses[i]
    return root.responses.indexOf(r)
  }
  property var responses: []
  property int currentTab: 0   // 0 = text, 1 = images, 2 = screenshots, 3 = canned
  property int hoverIndex: -1
  property bool editing: false
  property int editIndex: -1
  property string editLabel: ""
  property string editText: ""

  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/canned-responses.json"
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property bool opened: panelController.open
  readonly property int panelContentWidth: Style.space(360)

  function isImageInfo(text) {
    if (typeof text !== "string") return false
    var t = text.trim()
    if (!t) return true
    if (/^data:image\//i.test(t)) return true
    if (/^(file:\/\/)?.*\.(png|jpe?g|webp|gif|bmp|tiff|avif)$/i.test(t)) {
      if (!t.includes("\n") && t.length < 500) return true
    }
    if (/<img\b/i.test(t) && !t.includes("\n") && t.length < 2000) return true
    return false
  }

  function parseHistory(raw) {
    var texts = []
    var images = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (!Array.isArray(parsed)) return
      for (var i = 0; i < parsed.length; i++) {
        var e = parsed[i]
        if (!e) continue
        if (e.type === "text" && typeof e.text === "string" && e.text.length > 0 && !root.isImageInfo(e.text))
          texts.push(e)
        else if (e.type === "image" && e.path)
          images.push(e)
      }
    } catch (err) { /* ignore */ }
    root.texts = texts
    root.images = images
    root.refreshImageHashes()
  }

  function refreshImageHashes() {
    var paths = []
    for (var i = 0; i < root.images.length; i++) {
      var e = root.images[i]
      if (e && e.path) paths.push(e.path)
    }
    if (paths.length === 0) {
      root.imageHashes = {}
      root.applyScreenshotExclusion()
      return
    }
    hashProc.command = ["md5sum"].concat(paths)
    hashProc.running = true
  }

  function parseImageHashes(raw) {
    var map = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var sp = line.indexOf(" ")
      var hash = line.slice(0, sp)
      var path = line.slice(sp + 1).trim()
      map[path] = hash
    }
    root.imageHashes = map
    root.applyScreenshotExclusion()
  }

  // Screenshots are shown in the Screenshots tab; drop matching clipboard
  // image entries (identical content, e.g. omarchy-capture auto-copies) so
  // nothing appears twice.
  function applyScreenshotExclusion() {
    var filtered = []
    var changed = false
    for (var i = 0; i < root.images.length; i++) {
      var e = root.images[i]
      if (e && e.path) {
        var h = root.imageHashes[e.path]
        if (h && root.screenshotHashes[h]) { changed = true; continue }
      }
      filtered.push(e)
    }
    if (changed) root.images = filtered
  }

  function screenShotDirFallback() {
    return Quickshell.env("OMARCHY_SCREENSHOT_DIR")
      || Quickshell.env("XDG_PICTURES_DIR")
      || Quickshell.env("HOME") + "/Pictures"
  }

  function refreshScreenshots() {
    if (screenshotProc.running) {
      root.screenshotRefreshQueued = true
      return
    }
    screenshotProc.command = ["bash", "-c",
      "[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs; dir=${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}; "
      + "if [[ -d $dir ]]; then find \"$dir\" -maxdepth 1 -name 'screenshot-*.png' -printf '%T@ %p\\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | xargs -r -d '\\n' md5sum; fi"]
    screenshotProc.running = true
  }

  function parseScreenshots(raw) {
    var list = []
    var hashes = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var sp = line.indexOf(" ")
      var hash = line.slice(0, sp)
      var path = line.slice(sp + 1).trim()
      list.push({ type: "image", mime: "image/png", path: path })
      hashes[hash] = true
    }
    root.screenshots = list
    root.screenshotHashes = hashes
    root.applyScreenshotExclusion()
  }

  function screenshotRows() {
    var cols = Math.max(1, Math.floor((root.panelContentWidth - Style.space(8)) / Style.space(88)))
    return Math.ceil(Math.max(1, root.screenshots.length) / cols)
  }

  function preview(text) {
    var t = String(text || "").replace(/\s+/g, " ")
    if (t.length > 64) t = t.substring(0, 64) + "…"
    return t
  }

  function imageRows() {
    var cols = Math.max(1, Math.floor((root.panelContentWidth - Style.space(8)) / Style.space(88)))
    return Math.ceil(Math.max(1, root.images.length) / cols)
  }

  function universalPasteCommand() {
    return "sleep 0.4"
      + " && if jq -e 'any(.tags[]?; startswith(\"terminal\"))' <(hyprctl activewindow -j) >/dev/null 2>&1; then M=SHIFT; K=Insert; else M=CTRL; K=V; fi"
      + " && hyprctl dispatch \"hl.dsp.send_key_state({ mods = \\\"$M\\\", key = \\\"$K\\\", state = \\\"down\\\" })\""
      + " && sleep 0.05"
      + " && hyprctl dispatch \"hl.dsp.send_key_state({ mods = \\\"$M\\\", key = \\\"$K\\\", state = \\\"up\\\" })\""
  }

  function pasteText(i) {
    var entry = root.texts[i]
    if (!entry) return
    root.close()
    var script = Util.shellQuote(root.omarchyPath + "/bin/omarchy-clipboard-paste-text")
      + " --copy-only " + Util.shellQuote(entry.text)
    Util.execDetached(script + " && " + root.universalPasteCommand())
  }

  function pasteImage(i) {
    var entry = root.images[i]
    if (!entry) return
    root.close()
    var script = Util.shellQuote(root.omarchyPath + "/bin/omarchy-clipboard-paste-file")
      + " --copy-only " + Util.shellQuote(entry.mime || "image/png") + " " + Util.shellQuote(entry.path)
    Util.execDetached(script + " && " + root.universalPasteCommand())
  }

  function basename(path) {
    var parts = String(path || "").split("/")
    return parts[parts.length - 1] || ""
  }

  function inTextSnippets(text) {
    for (var i = 0; i < root.responses.length; i++) {
      var r = root.responses[i]
      if (r.type !== "image" && r.text === text) return true
    }
    return false
  }

  function inImageSnippets(path) {
    for (var i = 0; i < root.responses.length; i++) {
      var r = root.responses[i]
      if (r.type === "image" && r.path === path) return true
    }
    return false
  }

  function pasteScreenshot(i) {
    var entry = root.screenshots[i]
    if (!entry) return
    root.close()
    var script = Util.shellQuote(root.omarchyPath + "/bin/omarchy-clipboard-paste-file")
      + " --copy-only " + Util.shellQuote(entry.mime || "image/png") + " " + Util.shellQuote(entry.path)
    Util.execDetached(script + " && " + root.universalPasteCommand())
  }

  function addScreenshotToSnippets(i) {
    var entry = root.screenshots[i]
    if (!entry) return
    if (root.inImageSnippets(entry.path)) return
    var list = root.responses.slice()
    list.push({
      label: root.basename(entry.path),
      type: "image",
      mime: entry.mime || "image/png",
      path: entry.path
    })
    root.responses = list
    root.save()
  }

  function clearTexts() {
    var kept = []
    for (var i = 0; i < root.texts.length; i++) {
      var e = root.texts[i]
      if (e && e.type !== "text") kept.push(e)
    }
    root.texts = []
    try {
      var parsed = JSON.parse(String(historyFile.text() || "[]"))
      if (Array.isArray(parsed)) {
        var next = []
        for (var j = 0; j < parsed.length; j++) {
          var entry = parsed[j]
          if (entry && entry.type !== "text") next.push(entry)
        }
        historyFile.setText(JSON.stringify(next, null, 2) + "\n")
      }
    } catch (err) { /* ignore */ }
  }

  function deleteText(i) {
    var entry = root.texts[i]
    if (!entry) return
    try {
      var parsed = JSON.parse(String(historyFile.text() || "[]"))
      if (Array.isArray(parsed)) {
        var next = []
        for (var j = 0; j < parsed.length; j++) {
          var e = parsed[j]
          if (!(e && e.type === "text" && e.text === entry.text)) next.push(e)
        }
        historyFile.setText(JSON.stringify(next, null, 2) + "\n")
      }
    } catch (err) { /* ignore */ }
    var list = root.texts.slice()
    list.splice(i, 1)
    root.texts = list
  }

  function clearImages() {
    var kept = []
    for (var i = 0; i < root.images.length; i++) {
      var e = root.images[i]
      if (e && e.type !== "image") kept.push(e)
    }
    root.images = []
    try {
      var parsed = JSON.parse(String(historyFile.text() || "[]"))
      if (Array.isArray(parsed)) {
        var next = []
        for (var j = 0; j < parsed.length; j++) {
          var entry = parsed[j]
          if (entry && entry.type !== "image") next.push(entry)
        }
        historyFile.setText(JSON.stringify(next, null, 2) + "\n")
      }
    } catch (err) { /* ignore */ }
  }

  function clearScreenshots() {
    root.screenshots = []
    Util.execDetached(
      "[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs; dir=${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}; "
      + "find \"$dir\" -maxdepth 1 -name 'screenshot-*.png' -delete 2>/dev/null")
  }

  function deleteImage(i) {
    var entry = root.images[i]
    if (!entry) return
    try {
      var parsed = JSON.parse(String(historyFile.text() || "[]"))
      if (Array.isArray(parsed)) {
        var next = []
        for (var j = 0; j < parsed.length; j++) {
          var e = parsed[j]
          if (!(e && e.type === "image" && e.path === entry.path)) next.push(e)
        }
        historyFile.setText(JSON.stringify(next, null, 2) + "\n")
      }
    } catch (err) { /* ignore */ }
    var list = root.images.slice()
    list.splice(i, 1)
    root.images = list
  }

  function deleteScreenshot(i) {
    var entry = root.screenshots[i]
    if (!entry) return
    Util.execDetached("rm -f " + Util.shellQuote(entry.path))
    var list = root.screenshots.slice()
    list.splice(i, 1)
    root.screenshots = list
  }

  function addTextToSnippets(i) {
    var entry = root.texts[i]
    if (!entry || !entry.text) return
    if (root.inTextSnippets(entry.text)) return
    root.addResponse(root.preview(entry.text), entry.text)
  }

  function addImageToSnippets(i) {
    var entry = root.images[i]
    if (!entry) return
    if (root.inImageSnippets(entry.path)) return
    var list = root.responses.slice()
    list.push({
      label: root.basename(entry.path),
      type: "image",
      mime: entry.mime || "image/png",
      path: entry.path
    })
    root.responses = list
    root.save()
  }

  function pasteResponse(i) {
    var entry = root.responses[i]
    if (!entry) return
    root.close()
    if (entry.type === "image") {
      var script = Util.shellQuote(root.omarchyPath + "/bin/omarchy-clipboard-paste-file")
        + " --copy-only " + Util.shellQuote(entry.mime || "image/png") + " " + Util.shellQuote(entry.path)
    } else {
      script = Util.shellQuote(root.omarchyPath + "/bin/omarchy-clipboard-paste-text")
        + " --copy-only " + Util.shellQuote(entry.text || "")
    }
    Util.execDetached(script + " && " + root.universalPasteCommand())
  }

  function open() { panelController.show() }
  function close() { panelController.hide() }
  function toggle() { root.opened ? close() : open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  function openAdd() {
    root.editing = true
    root.editIndex = -1
    root.editLabel = ""
    root.editText = ""
  }

  function openEdit(index) {
    var r = root.responses[index]
    if (!r) return
    root.editing = true
    root.editIndex = index
    root.editLabel = r.label
    root.editText = r.text
  }

  function save() {
    dataFile.setText(JSON.stringify(root.responses, null, 2) + "\n")
  }

  function addResponse(label, text) {
    var list = root.responses.slice()
    list.push({ label: label, text: text })
    root.responses = list
    root.save()
  }

  function updateResponse(index, label, text) {
    var list = root.responses.slice()
    var prev = list[index] || {}
    list[index] = {
      label: label,
      type: prev.type || "text",
      mime: prev.mime,
      path: prev.path,
      text: text
    }
    root.responses = list
    root.save()
  }

  function deleteResponse(index) {
    var list = root.responses.slice()
    list.splice(index, 1)
    root.responses = list
    root.save()
  }

  function clearResponses() {
    root.responses = []
    root.save()
  }

  function contentHeightFor() {
    var h = Style.space(32) // header
    h += 1 // separator
    h += Style.space(50) // tab bar
    if (root.currentTab === 0) {
      h += Style.space(6)
      h += Math.max(1, root.filteredTexts.length) * Style.space(52) + Math.max(0, root.filteredTexts.length - 1) * Style.space(4)
      h += Style.space(42) // clear-all row
    } else if (root.currentTab === 1) {
      h += Style.space(6)
      h += root.imageRows() * Style.space(88) + (root.imageRows() - 1) * Style.space(8)
      h += Style.space(42) // clear-all row
    } else if (root.currentTab === 2) {
      h += Style.space(6)
      h += root.screenshotRows() * Style.space(88) + (root.screenshotRows() - 1) * Style.space(8)
      h += Style.space(42) // clear-all row
    } else {
      h += Style.space(10)
      if (root.editing) {
        h += Style.space(20) // title
        h += Style.space(10) // spacing
        h += Style.space(36) // label input
        h += Style.space(10) // spacing
        h += Style.space(120) // body text area
        h += Style.space(10) // spacing
        h += Style.space(36) // buttons
      } else {
        h += Style.space(36) // search/clear row spacer
        h += Style.space(36) // add button
        for (var fi = 0; fi < root.filteredResponses.length; fi++) {
          var fr = root.filteredResponses[fi]
          h += (fr && fr.type === "image" ? Style.space(88) : Style.space(44))
        }
        h += Math.max(0, root.filteredResponses.length - 1) * Style.space(4)
        h += Style.space(4)
        h += Style.space(10)
      }
    }
    return h
  }

  onOpenedChanged: {
    if (!root.opened) {
      root.editing = false
      root.editIndex = -1
      root.editLabel = ""
      root.editText = ""
      root.textFilter = ""
      root.favFilter = ""
      root.hoverPreviewPath = ""
    } else {
      root.refreshScreenshots()
    }
  }

  onCurrentTabChanged: root.hoverPreviewPath = ""

  property bool screenshotRefreshQueued: false

  Process {
    id: screenshotProc
    stdout: StdioCollector {
      id: screenshotOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.parseScreenshots(String(screenshotOut.text || ""))
      if (root.screenshotRefreshQueued) {
        root.screenshotRefreshQueued = false
        root.refreshScreenshots()
      }
    }
  }

  Process {
    id: hashProc
    stdout: StdioCollector {
      id: hashOut
      waitForEnd: true
    }
    onExited: root.parseImageHashes(String(hashOut.text || ""))
  }

  Timer {
    id: screenshotTimer
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: root.refreshScreenshots()
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.parseHistory(text())
    onLoadFailed: { root.texts = []; root.images = [] }
    onFileChanged: reload()
  }

  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var raw = text() || "[]"
      try {
        var parsed = JSON.parse(raw)
        root.responses = Array.isArray(parsed) ? parsed : []
      } catch (e) { root.responses = [] }
    }
    onLoadFailed: root.responses = []
    onFileChanged: reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0c6"
    tooltipText: "SuperClip"
    onPressed: function(b) {
      if (b === Qt.LeftButton || b === Qt.MiddleButton) root.toggle()
    }
  }

  PanelController {
    id: panelController
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(root.panelContentWidth)
    contentHeight: panel.fittedContentHeight(Math.min(Style.space(560), root.contentHeightFor()))

    Item {
      anchors.fill: parent

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(32)
          Layout.topMargin: Style.space(0)
          spacing: Style.space(8)

          Text {
            text: "\uf0c6"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            verticalAlignment: Text.AlignVCenter
          }

          Text {
            text: "SuperClip"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }

          Item { Layout.fillWidth: true }
        }

        // Tab bar
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(50)
          spacing: Style.space(6)

          component TabButton: Rectangle {
            id: tabBtn
            property string icon: ""
            property string tooltip: ""
            property int tabIndex: 0
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(46)
            radius: Style.space(6)
            color: tabBtnArea.containsMouse || root.currentTab === tabIndex
              ? Util.alpha(Color.accent, root.currentTab === tabIndex ? 0.25 : 0.12)
              : Util.alpha(Color.popups.text, 0.06)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(1)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: icon
                color: root.currentTab === tabIndex ? Color.accent : Color.popups.text
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Math.round(Style.font.caption * 1.4)
                font.bold: root.currentTab === tabIndex
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tabBtn.tooltip
                color: root.currentTab === tabIndex ? Color.accent : Util.alpha(Color.popups.text, 0.7)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: root.currentTab === tabIndex
              }
            }

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              width: root.currentTab === tabIndex ? parent.width * 0.4 : 0
              height: 2
              color: Color.accent
              radius: 1
            }

            MouseArea {
              id: tabBtnArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.currentTab = tabIndex
            }
          }

          TabButton { icon: "\uf15c"; tooltip: "Text"; tabIndex: 0 }       // text
          TabButton { icon: "\uf03e"; tooltip: "Images"; tabIndex: 1 }     // images
          TabButton { icon: "\uf030"; tooltip: "Screenshots"; tabIndex: 2 } // screenshots
          TabButton { icon: "\uf0c6"; tooltip: "SuperClips"; tabIndex: 3 }   // superclips
        }

        // Text list
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: root.currentTab === 0
            ? Math.max(1, root.filteredTexts.length) * Style.space(52) + Math.max(0, root.filteredTexts.length - 1) * Style.space(4) + Style.space(48)
            : 0
          visible: root.currentTab === 0
          clip: true

          SearchBox {
            width: parent.width - Style.space(122)
            placeholder: "Search text"
            onSearchChanged: root.textFilter = value
          }

          ClearAllButton {
            onClicked: root.clearTexts()
          }

          Column {
            anchors.fill: parent
            anchors.topMargin: Style.space(42)
            anchors.bottomMargin: Style.space(6)
            spacing: Style.space(4)

            Repeater {
              model: root.filteredTexts

              Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: Style.space(52)
                radius: Style.space(6)
                color: root.hoverIndex === index ? Util.alpha(Color.accent, 0.2) : Util.alpha(Color.popups.text, 0.06)

                MouseArea {
                  id: textRowArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.hoverIndex = index
                  onClicked: root.pasteText(root.textOriginalIndex(index))
                }

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(70)
                  text: root.preview(modelData.text)
                  color: root.bar ? root.bar.foreground : Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  verticalAlignment: Text.AlignVCenter
                  wrapMode: Text.Wrap
                }

                Text {
                  id: textStar
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(28)
                  height: Style.space(28)
                  text: "\uf0c6"
                  color: (textStarArea.containsMouse || root.inTextSnippets(modelData.text)) ? "#fbbf24" : Util.alpha(Color.popups.text, 0.45)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.round(Style.font.body)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  z: 2

                  PanelToolTip {
                    visible: textStarArea.containsMouse
                    text: "Add To Snippets"
                  }

                  MouseArea {
                    id: textStarArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverIndex = index
                    onClicked: root.addTextToSnippets(root.textOriginalIndex(index))
                  }
                }

                Text {
                  id: textDelete
                  anchors.right: textStar.left
                  anchors.rightMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(28)
                  height: Style.space(28)
                  text: "\uf1f8"
                  color: textDeleteArea.containsMouse ? Color.urgent : Util.alpha(Color.urgent, 0.6)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.round(Style.font.body)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  z: 2

                  PanelToolTip {
                    visible: textDeleteArea.containsMouse
                    text: "Delete"
                  }

                  MouseArea {
                    id: textDeleteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverIndex = index
                    onClicked: root.deleteText(root.textOriginalIndex(index))
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.filteredTexts.length === 0
              text: root.texts.length === 0 ? "No clipboard text" : "No matches"
              color: Util.alpha(Color.popups.text, 0.5)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(20)
              bottomPadding: Style.space(20)
            }
          }
        }

        // Image grid
        Item {
          id: gridArea
          Layout.fillWidth: true
          Layout.preferredHeight: root.currentTab === 1
            ? root.imageRows() * Style.space(88) + (root.imageRows() - 1) * Style.space(8) + Style.space(48)
            : 0
          visible: root.currentTab === 1
          clip: true

          ClearAllButton {
            onClicked: root.clearImages()
          }

          Grid {
            anchors.fill: parent
            anchors.topMargin: Style.space(42)
            anchors.bottomMargin: Style.space(6)
            spacing: Style.space(8)
            columns: Math.max(1, Math.floor((root.panelContentWidth - Style.space(8)) / Style.space(88)))

            Repeater {
              model: root.images

              Rectangle {
                required property var modelData
                required property int index
                width: Style.space(88)
                height: Style.space(88)
                radius: Style.space(6)
                color: root.hoverIndex === index ? Util.alpha(Color.accent, 0.2) : "transparent"
                border.width: 1
                border.color: Util.alpha(Color.popups.text, 0.15)
                clip: true

                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  source: "file://" + modelData.path
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  sourceSize.width: Style.space(88)
                  sourceSize.height: Style.space(88)
                }

                MouseArea {
                  id: thumbArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.hoverIndex = index
                  onClicked: root.pasteImage(index)
                }

                Text {
                  id: imageStar
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(2)
                  width: Style.space(28)
                  height: Style.space(28)
                  text: "\uf0c6"
                  color: imageStarArea.containsMouse || root.inImageSnippets(modelData.path) ? "#fbbf24" : "white"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.round(Style.font.body)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  opacity: root.hoverIndex === index || imageStarArea.containsMouse || root.inImageSnippets(modelData.path) ? 1 : 0.7
                  style: Text.Outline
                  styleColor: "black"
                  z: 2

                  PanelToolTip {
                    visible: imageStarArea.containsMouse
                    text: "Add To Snippets"
                  }

                  MouseArea {
                    id: imageStarArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverIndex = index
                    onClicked: root.addImageToSnippets(index)
                  }
                }

                Text {
                  id: imageDelete
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(2)
                  width: Style.space(28)
                  height: Style.space(28)
                  text: "\uf1f8"
                  color: imageDeleteArea.containsMouse ? Color.urgent : "white"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.round(Style.font.body)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  opacity: root.hoverIndex === index || imageDeleteArea.containsMouse ? 1 : 0
                  style: Text.Outline
                  styleColor: "black"
                  z: 3

                  PanelToolTip {
                    visible: imageDeleteArea.containsMouse
                    text: "Delete"
                  }

                  MouseArea {
                    id: imageDeleteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverIndex = index
                    onClicked: root.deleteImage(index)
                  }
                }

                // Hover tracking only — shows the large preview, never steals clicks.
                MouseArea {
                  anchors.fill: parent
                  z: 50
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.hoverPreviewPath = modelData.path
                  onExited: root.hoverPreviewPath = ""
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.images.length === 0
            text: "No clipboard images"
            color: Util.alpha(Color.popups.text, 0.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        // Screenshots grid
        Item {
          id: shotArea
          Layout.fillWidth: true
          Layout.preferredHeight: root.currentTab === 2
            ? root.screenshotRows() * Style.space(88) + (root.screenshotRows() - 1) * Style.space(8) + Style.space(48)
            : 0
          visible: root.currentTab === 2
          clip: true

          ClearAllButton {
            onClicked: root.clearScreenshots()
          }

          Grid {
            anchors.fill: parent
            anchors.topMargin: Style.space(42)
            anchors.bottomMargin: Style.space(6)
            spacing: Style.space(8)
            columns: Math.max(1, Math.floor((root.panelContentWidth - Style.space(8)) / Style.space(88)))

            Repeater {
              model: root.screenshots

              Rectangle {
                required property var modelData
                required property int index
                width: Style.space(88)
                height: Style.space(88)
                radius: Style.space(6)
                color: root.hoverIndex === index ? Util.alpha(Color.accent, 0.2) : "transparent"
                border.width: 1
                border.color: Util.alpha(Color.popups.text, 0.15)
                clip: true

                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  source: "file://" + modelData.path
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  sourceSize.width: Style.space(88)
                  sourceSize.height: Style.space(88)
                }

                MouseArea {
                  id: shotThumbArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.hoverIndex = index
                  onClicked: root.pasteScreenshot(index)
                }

                Text {
                  id: shotStar
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(2)
                  width: Style.space(28)
                  height: Style.space(28)
                  text: "\uf0c6"
                  color: shotStarArea.containsMouse || root.inImageSnippets(modelData.path) ? "#fbbf24" : "white"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.round(Style.font.body)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  opacity: root.hoverIndex === index || shotStarArea.containsMouse || root.inImageSnippets(modelData.path) ? 1 : 0.7
                  style: Text.Outline
                  styleColor: "black"
                  z: 2

                  PanelToolTip {
                    visible: shotStarArea.containsMouse
                    text: "Add To Snippets"
                  }

                  MouseArea {
                    id: shotStarArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverIndex = index
                    onClicked: root.addScreenshotToSnippets(index)
                  }
                }

                Text {
                  id: shotDelete
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(2)
                  width: Style.space(28)
                  height: Style.space(28)
                  text: "\uf1f8"
                  color: shotDeleteArea.containsMouse ? Color.urgent : "white"
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.round(Style.font.body)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  opacity: root.hoverIndex === index || shotDeleteArea.containsMouse ? 1 : 0
                  style: Text.Outline
                  styleColor: "black"
                  z: 3

                  PanelToolTip {
                    visible: shotDeleteArea.containsMouse
                    text: "Delete"
                  }

                  MouseArea {
                    id: shotDeleteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverIndex = index
                    onClicked: root.deleteScreenshot(index)
                  }
                }

                // Hover tracking only — shows the large preview, never steals clicks.
                MouseArea {
                  anchors.fill: parent
                  z: 50
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.hoverPreviewPath = modelData.path
                  onExited: root.hoverPreviewPath = ""
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.screenshots.length === 0
            text: "No screenshots yet"
            color: Util.alpha(Color.popups.text, 0.5)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        // Canned responses
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: root.currentTab === 3 ? root.contentHeightFor() - Style.space(32) - 1 - Style.space(50) : 0
          visible: root.currentTab === 3
          clip: true

          SearchBox {
            visible: !root.editing
            width: parent.width - Style.space(122)
            placeholder: "Search SuperClips"
            onSearchChanged: root.favFilter = value
          }

          ClearAllButton {
            visible: !root.editing
            onClicked: root.clearResponses()
          }

          Column {
            anchors.fill: parent
            spacing: 0

            // Spacer clears the absolute search/clear-all row above.
            Item {
              width: parent.width
              height: Style.space(36)
              visible: !root.editing
            }

            // Add button (list mode)
            Rectangle {
              id: addButton
              width: parent.width * 0.33
              height: Style.space(36)
              radius: Style.space(6)
              color: addBtnArea.containsMouse ? Util.alpha(Color.accent, 0.2) : Util.alpha(Color.popups.text, 0.06)
              visible: !root.editing

              Text {
                anchors.centerIn: parent
                text: "+  Add"
                color: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: addBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openAdd()
              }
            }

            // Response list
            Column {
              id: listColumn
              width: parent.width
              topPadding: Style.space(4)
              bottomPadding: Style.space(10)
              spacing: Style.space(4)
              visible: !root.editing

              Repeater {
                model: root.filteredResponses

                Item {
                  required property var modelData
                  required property int index
                  width: listColumn.width
                  height: modelData.type === "image" ? Style.space(88) : Style.space(44)

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(6)
                    color: root.hoverIndex === index ? Util.alpha(Color.accent, 0.2) : "transparent"

                    RowLayout {
                      visible: modelData.type !== "image"
                      anchors.fill: parent
                      anchors.margins: Style.space(8)
                      spacing: Style.space(8)

                      Image {
                        visible: modelData.type === "image"
                        Layout.preferredWidth: Style.space(40)
                        Layout.preferredHeight: Style.space(40)
                        Layout.alignment: Qt.AlignVCenter
                        source: modelData.type === "image" ? "file://" + modelData.path : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize.width: Style.space(40)
                        sourceSize.height: Style.space(40)
                        clip: true
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                          Layout.fillWidth: true
                          text: modelData.label || "Untitled"
                          elide: Text.ElideRight
                          maximumLineCount: 1
                          color: Color.popups.text
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.body
                          font.bold: true
                        }

                        Text {
                          Layout.fillWidth: true
                          text: modelData.type === "image"
                            ? (root.basename(modelData.path) || modelData.mime || "image")
                            : (modelData.text || "").split("\n")[0]
                          elide: Text.ElideRight
                          maximumLineCount: 1
                          color: Util.alpha(Color.popups.text, 0.5)
                          font.family: root.bar ? root.bar.fontFamily : Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    // Large thumbnail for image favourites (same tile size as the Images grid).
                    Image {
                      visible: modelData.type === "image"
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.margins: Style.space(2)
                      width: Style.space(88)
                      height: Style.space(88)
                      source: modelData.type === "image" ? "file://" + modelData.path : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      sourceSize.width: Style.space(88)
                      sourceSize.height: Style.space(88)
                      clip: true
                    }
                  }

                  // Icon buttons layer above the row so their clicks win.
                  Item {
                    id: iconsLayer
                    anchors.right: parent.right
                    anchors.bottom: modelData.type === "image" ? parent.bottom : undefined
                    anchors.verticalCenter: modelData.type === "image" ? undefined : parent.verticalCenter
                    anchors.rightMargin: Style.space(4)
                    anchors.bottomMargin: Style.space(4)
                    width: Style.space(28) * 2 + Style.space(8)
                    height: Style.space(28)
                    z: 2

                    Text {
                      visible: modelData.type !== "image"
                      x: Style.space(0)
                      width: Style.space(28)
                      height: Style.space(28)
                      text: "\uf044"
                      color: Util.alpha(Color.popups.text, 0.5)
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Math.round(Style.font.body)
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openEdit(root.responseOriginalIndex(index))
                      }
                    }

                    Text {
                      x: Style.space(28) + Style.space(8)
                      width: Style.space(28)
                      height: Style.space(28)
                      text: "\uf1f8"
                      color: Color.urgent
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Math.round(Style.font.body)
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.deleteResponse(root.responseOriginalIndex(index))
                      }
                    }
                  }

                  // Hover tracking only — shows the large preview for image favourites.
                  MouseArea {
                    anchors.fill: parent
                    z: 50
                    hoverEnabled: true
                    enabled: modelData.type === "image"
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoverPreviewPath = modelData.path
                    onExited: root.hoverPreviewPath = ""
                  }

                  // Row-level paste on the label area.
                  MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.hoverIndex = index
                    onClicked: root.pasteResponse(root.responseOriginalIndex(index))
                  }
                }
              }

              Text {
                width: listColumn.width
                visible: root.filteredResponses.length === 0
                text: root.responses.length === 0 ? "No saved responses" : "No matches"
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(20)
                bottomPadding: Style.space(20)
              }
            }

            // Edit form
            Column {
              id: formColumn
              width: parent.width
              topPadding: Style.space(10)
              spacing: Style.space(10)
              visible: root.editing

              Text {
                text: root.editIndex >= 0 ? "Edit Response" : "Add SuperClip"
                color: Color.popups.text
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Rectangle {
                width: formColumn.width
                height: Style.space(36)
                radius: Style.space(4)
                color: "transparent"
                border.width: 1
                border.color: Util.alpha(Color.popups.text, 0.2)

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  visible: labelInput.text === ""
                  text: "Title"
                  color: Util.alpha(Color.popups.text, 0.35)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }

                TextInput {
                  id: labelInput
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  color: Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  verticalAlignment: TextInput.AlignVCenter
                  clip: true
                  text: root.editLabel
                  onTextChanged: root.editLabel = text
                  KeyNavigation.tab: bodyEdit
                  KeyNavigation.backtab: bodyEdit
                }
              }

              Rectangle {
                width: formColumn.width
                height: Style.space(120)
                radius: Style.space(4)
                color: "transparent"
                border.width: 1
                border.color: Util.alpha(Color.popups.text, 0.2)
                clip: true

                Text {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  visible: bodyEdit.text === ""
                  text: "Body"
                  color: Util.alpha(Color.popups.text, 0.35)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  verticalAlignment: Text.AlignTop
                  wrapMode: Text.Wrap
                  maximumLineCount: 10
                  elide: Text.ElideRight
                }

                TextEdit {
                  id: bodyEdit
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  color: Color.popups.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  text: root.editText
                  onTextChanged: root.editText = text
                  KeyNavigation.tab: labelInput
                  KeyNavigation.backtab: labelInput
                }
              }

              RowLayout {
                width: formColumn.width
                spacing: Style.space(8)

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(36)
                  radius: Style.space(6)
                  color: cancelArea.containsMouse ? Util.alpha(Color.popups.text, 0.12) : Util.alpha(Color.popups.text, 0.06)
                  border.width: 1
                  border.color: Util.alpha(Color.popups.text, 0.2)

                  Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Color.popups.text
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                  }
                }

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(36)
                  radius: Style.space(6)
                  color: saveArea.containsMouse ? Qt.darker(Color.accent, 1.1) : Color.accent

                  Text {
                    anchors.centerIn: parent
                    text: root.editIndex >= 0 ? "Save" : "Add"
                    color: "#ffffff"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  MouseArea {
                    id: saveArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.editIndex >= 0)
                        root.updateResponse(root.editIndex, root.editLabel.trim(), root.editText.trim())
                      else
                        root.addResponse(root.editLabel.trim(), root.editText.trim())
                      Qt.callLater(function() { root.close() })
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // Hover preview overlay for image thumbnails.
    Rectangle {
      id: hoverPreview
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(8)
      width: Math.min(Style.space(280), parent.width - Style.space(16))
      height: Math.min(Style.space(280), parent.height - Style.space(16))
      radius: Style.space(6)
      z: 100
      visible: root.hoverPreviewPath !== ""
      color: "transparent"
      clip: true

      Image {
        anchors.fill: parent
        anchors.margins: Style.space(2)
        source: "file://" + root.hoverPreviewPath
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: Math.max(Style.space(280), Math.round(width * 2))
        sourceSize.height: Math.max(Style.space(280), Math.round(height * 2))
      }
    }
  }

  component SearchBox: Rectangle {
    id: searchBox
    signal searchChanged(string value)
    property string placeholder: ""
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(6)
    height: Style.space(28)
    radius: Style.space(6)
    color: searchInput.activeFocus ? Util.alpha(Color.accent, 0.12) : Util.alpha(Color.popups.text, 0.06)
    border.width: 1
    border.color: searchInput.activeFocus ? Util.alpha(Color.accent, 0.6) : Util.alpha(Color.popups.text, 0.15)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "\uf002"
      color: Util.alpha(Color.popups.text, 0.5)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.fill: parent
      anchors.leftMargin: Style.space(26)
      anchors.rightMargin: Style.space(8)
      text: searchInput.text ? "" : searchBox.placeholder
      color: Util.alpha(Color.popups.text, 0.35)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    TextInput {
      id: searchInput
      anchors.fill: parent
      anchors.leftMargin: Style.space(26)
      anchors.rightMargin: Style.space(8)
      color: Color.popups.text
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      selectByMouse: true
      onTextChanged: searchBox.searchChanged(text)
    }
  }

  component ClearAllButton: Rectangle {
    id: clearBtn
    signal clicked()
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(6)
    width: Style.space(104)
    height: Style.space(28)
    radius: Style.space(6)
    color: clearBtnArea.containsMouse ? Util.alpha(Color.urgent, 0.25) : Util.alpha(Color.urgent, 0.08)
    border.width: 1
    border.color: clearBtnArea.containsMouse ? Color.urgent : Util.alpha(Color.urgent, 0.4)

    Text {
      anchors.centerIn: parent
      text: "\uf1f8  Clear All"
      color: Color.urgent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: clearBtnArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: clearBtn.clicked()
    }
  }

}