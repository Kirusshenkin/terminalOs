/// Why a key is worth replacing. The words are the interface's business.
public enum KeyWeakness: Sendable, Equatable {
    /// DSA: deprecated and unsafe.
    case dsa
    /// RSA shorter than 3072 bits.
    case shortRSA(bits: Int)

    public init?(algorithm: String, bits: Int?) {
        if algorithm == "ssh-dss" {
            self = .dsa
        } else if algorithm == "ssh-rsa", let bits, bits < 3072 {
            self = .shortRSA(bits: bits)
        } else {
            return nil
        }
    }
}
