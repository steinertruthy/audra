import AppKit
import SwiftUI

/// Menu bar commands. Every editor shortcut lives here so it is discoverable in the menus.
/// Single-key shortcuts (Space, arrows, ⌫, N, M, F) never steal typing: when a text field has focus,
/// the key is handed back to the text instead of running the command.
struct AudraCommands: Commands {
    let model: AppModel

    /// Text view being edited, if any.
    @MainActor private static var editingText: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    /// Runs `action`, or forwards the key to the focused text field.
    @MainActor private static func command(_ action: () -> Void, text: (NSTextView) -> Void) {
        if let textView = editingText { text(textView) } else { action() }
    }

    var body: some Commands {
        let editor = model.editor

        CommandGroup(replacing: .newItem) {
            Button(tr("Novo Projeto de Edição")) { model.newProject() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button(tr("Transcrever Vídeos…")) { model.presentImporter() }
                .keyboardShortcut("o")
            if editor != nil {
                Button(tr("Adicionar Mídia ao Projeto…")) { editor?.presentImporter() }
                    .keyboardShortcut("i")
                Divider()
                Button(tr("Exportar Vídeo…")) { model.exportRequest += 1 }
                    .keyboardShortcut("e")
                Button(tr("Fechar Projeto")) { model.closeEditor() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }

        CommandGroup(after: .newItem) {
            Button(tr("Cancelar Processamento")) {
                if let id = model.selectedRecording?.id { model.processing.cancel(id) }
            }
            .keyboardShortcut(".")
            .disabled(!(model.selectedRecording?.status.isActive ?? false))
        }

        // Undo/redo: text fields keep their own history; otherwise the editor's.
        CommandGroup(replacing: .undoRedo) {
            Button(editor?.undoName.map { tr("Desfazer %@", $0) } ?? tr("Desfazer")) {
                if Self.editingText != nil || editor == nil {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    editor?.undo()
                }
            }
            .keyboardShortcut("z")
            Button(editor?.redoName.map { tr("Refazer %@", $0) } ?? tr("Refazer")) {
                if Self.editingText != nil || editor == nil {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    editor?.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button(tr("Copiar Transcrição Completa")) {
                if let r = model.selectedRecording {
                    Exporter.copy(TranscriptRenderer.plainText(title: r.title, segments: r.decodeSegments()))
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.selectedRecording?.segmentCount ?? 0 == 0)
        }

        CommandGroup(after: .textEditing) {
            Button(tr("Buscar na Biblioteca")) { model.searchFocusRequest += 1 }
                .keyboardShortcut("k")
                .disabled(editor != nil)
            Button(tr("Buscar na Transcrição")) { model.findRequest += 1 }
                .keyboardShortcut("f")
                .disabled(model.selectedRecording?.status != .completed)
        }

        CommandGroup(before: .toolbar) {
            if let editor {
                Button(tr("Aumentar Zoom da Timeline")) { editor.zoom(by: 1.5) }
                    .keyboardShortcut("=")
                Button(tr("Diminuir Zoom da Timeline")) { editor.zoom(by: 1 / 1.5) }
                    .keyboardShortcut("-")
                Divider()
                Button(editor.showLeftPanel ? tr("Ocultar Painel de Mídia") : tr("Mostrar Painel de Mídia")) {
                    withAnimation(Motion.smooth) { editor.showLeftPanel.toggle() }
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
                Button(editor.showInspector ? tr("Ocultar Propriedades") : tr("Mostrar Propriedades")) {
                    withAnimation(Motion.smooth) { editor.showInspector.toggle() }
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
            } else {
                ForEach(Array(ResultMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.label) { model.resultMode = mode }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            Divider()
        }

        CommandMenu(tr("Clipe")) {
            Button(tr("Dividir no Cursor")) { editor?.splitAtPlayhead() }
                .keyboardShortcut("b")
                .disabled(editor == nil)
            Button(tr("Duplicar")) { editor?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(editor?.selection.isEmpty ?? true)
            Button(tr("Excluir")) {
                Self.command({ editor?.deleteSelection() }, text: { $0.deleteBackward(nil) })
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(editor?.selection.isEmpty ?? true)
            Button(tr("Excluir e Fechar Espaço")) {
                Self.command({ editor?.deleteSelection(ripple: true) }, text: { $0.deleteBackward(nil) })
            }
            .keyboardShortcut(.delete, modifiers: .shift)
            .disabled(editor?.selection.isEmpty ?? true)
            Button(tr("Selecionar Todos os Clipes")) {
                Self.command({ editor?.selectAll() }, text: { $0.selectAll(nil) })
            }
            .disabled(editor == nil)
            Divider()
            Button(tr("Separar Áudio")) { editor?.detachAudio() }
                .disabled(editor?.singleSelectedClip?.mediaID == nil)
            Button(tr("Remover Pausas Longas")) { editor?.removeSilences() }
                .disabled(editor == nil)
            Divider()
            Button(tr("Adicionar Título")) { editor?.addText(.title()) }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(editor == nil)
            Button(tr("Adicionar Marcador")) {
                Self.command({ editor?.addMarker() }, text: { $0.insertText("m", replacementRange: $0.selectedRange()) })
            }
            .keyboardShortcut("m", modifiers: [])
            .disabled(editor == nil)
            Toggle(tr("Ímã de Alinhamento"), isOn: Binding(
                get: { editor?.snapping ?? false },
                set: { value in Self.command({ editor?.snapping = value }, text: { $0.insertText("n", replacementRange: $0.selectedRange()) }) }))
                .keyboardShortcut("n", modifiers: [])
                .disabled(editor == nil)
        }

        CommandMenu(tr("Reprodução")) {
            Button(tr("Reproduzir / Pausar")) {
                if let editor {
                    Self.command({ editor.togglePlayback() }, text: { $0.insertText(" ", replacementRange: $0.selectedRange()) })
                } else {
                    model.player?.togglePlayback()
                }
            }
            .keyboardShortcut(editor != nil ? .space : .return, modifiers: editor != nil ? [] : .command)

            if let editor {
                Divider()
                Button(tr("Quadro Anterior")) { Self.command({ editor.step(frames: -1) }, text: { $0.moveLeft(nil) }) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(tr("Próximo Quadro")) { Self.command({ editor.step(frames: 1) }, text: { $0.moveRight(nil) }) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button(tr("Voltar 1 Segundo")) { Self.command({ editor.jump(by: -1) }, text: { $0.moveLeftAndModifySelection(nil) }) }
                    .keyboardShortcut(.leftArrow, modifiers: .shift)
                Button(tr("Avançar 1 Segundo")) { Self.command({ editor.jump(by: 1) }, text: { $0.moveRightAndModifySelection(nil) }) }
                    .keyboardShortcut(.rightArrow, modifiers: .shift)
            }
            Divider()
            Button(tr("Voltar 5 Segundos")) {
                if let editor { editor.jump(by: -5) } else { model.player?.skip(by: -5) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button(tr("Avançar 5 Segundos")) {
                if let editor { editor.jump(by: 5) } else { model.player?.skip(by: 5) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            if let editor {
                Button(tr("Ir para o Início")) { editor.seek(to: 0) }
                    .keyboardShortcut(.home, modifiers: [])
                Button(tr("Ir para o Fim")) { editor.seek(to: editor.duration) }
                    .keyboardShortcut(.end, modifiers: [])
            }
            Divider()
            Menu(tr("Velocidade")) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button(tr("%@×", rate.formatted())) {
                        if let editor { editor.playbackRate = Float(rate) } else { model.player?.rate = Float(rate) }
                    }
                }
            }
            if let editor {
                Button(editor.theaterMode ? tr("Sair da Tela Cheia") : tr("Tela Cheia")) {
                    Self.command({ withAnimation(Motion.smooth) { editor.theaterMode.toggle() } },
                                 text: { $0.insertText("f", replacementRange: $0.selectedRange()) })
                }
                .keyboardShortcut("f", modifiers: [])
            }
        }
    }
}
