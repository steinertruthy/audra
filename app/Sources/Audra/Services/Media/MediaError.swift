import Foundation

enum MediaError: LocalizedError {
    case fileMissing(String)
    case unsupportedContainer(String)
    case noAudioTrack
    case unreadable(String)
    case conversionFailed(String)
    case emptyAudio
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let name):
            tr("O arquivo “%@” não foi encontrado. Ele pode ter sido movido, renomeado ou excluído.", name)
        case .unsupportedContainer(let ext):
            tr("O formato %@ não é lido nativamente pelo macOS. Para processá-lo, instale o FFmpeg (brew install ffmpeg) e tente novamente.", ext)
        case .noAudioTrack:
            tr("Este arquivo não possui uma faixa de áudio, então não há fala para transcrever.")
        case .unreadable(let detail):
            tr("Não foi possível ler a mídia. %@", detail)
        case .conversionFailed(let detail):
            tr("A conversão do arquivo falhou. %@", detail)
        case .emptyAudio:
            tr("O áudio extraído está vazio.")
        case .exportFailed(let detail):
            tr("A exportação do vídeo falhou. %@", detail)
        }
    }
}
