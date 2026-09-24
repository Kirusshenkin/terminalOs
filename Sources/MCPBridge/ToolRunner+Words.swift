import KeysKit

/// Слова, которыми мост отвечает ИИ-клиенту.
///
/// Пакеты отдают причины типами, а не фразами; интерфейс подбирает слова по
/// своей таблице, мост — здесь. Ответы моста пока только по-русски (#13).
extension ToolRunner {
    static func describe(_ weakness: KeyWeakness) -> String {
        switch weakness {
        case .dsa: "DSA — устарел и небезопасен"
        case .shortRSA(let bits): "RSA \(bits) бит — короче 3072"
        }
    }
}
