import Foundation
import Testing

@testable import HostsKit

/// Векторы — из эталонной `golang.org/x/crypto/nacl/secretbox` (Seal):
/// ключ, nonce, открытый текст, бокс. Длины выбраны на границах блоков
/// Salsa20 (64) и Poly1305 (16), где самодельный шифр ломается первым.
// swiftlint:disable line_length
// Hex-векторы длинные по природе: переносить строку внутри литерала — портить сверку с эталоном.
private let vectors: [(key: String, nonce: String, plain: String, box: String)] = [
    ("01080f161d242b323940474e555c636a71787f868d949ba2a9b0b7bec5ccd3da", "05121f2c394653606d7a8794a1aebbc8d5e2effc09162330", "", "d32c3cedb4b5adac5044b2e86783cd5e"),
    ("20272e353c434a51585f666d747b828990979ea5acb3bac1c8cfd6dde4ebf2f9", "1623303d4a5764717e8b98a5b2bfccd9e6f3000d1a273441", "01", "af564cbdc3780092865e6991390ec848de"),
    ("3f464d545b626970777e858c939aa1a8afb6bdc4cbd2d9e0e7eef5fc030a1118", "2734414e5b6875828f9ca9b6c3d0ddeaf704111e2b384552", "0203060b121b26334253667b92abc6", "be636d78dddfcde35c70fa1992afc6aad2dc33103ec4e8da0836522b0910dc"),
    ("5e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ff060d141b22293037", "3845525f6c798693a0adbac7d4e1eefb0815222f3c495663", "0304070c131c27344354677c93acc7e4", "2a1649bc7e5d72067a52c9cd4179e5bcee3e41ec090861c743024368d4bcb469"),
    ("7d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb020910171e252c333a41484f56", "495663707d8a97a4b1becbd8e5f2ff0c192633404d5a6774", "0405080d141d28354455687d94adc8e504", "e9265e83090384ebaef880c30d4849da54ea66dbceacd03a546596ce15639bd234"),
    ("9ca3aab1b8bfc6cdd4dbe2e9f0f7fe050c131a21282f363d444b525960676e75", "5a6774818e9ba8b5c2cfdce9f603101d2a3744515e6b7885", "0506090e151e29364556697e95aec9e60526496e95bee9164576a9de154e89", "30e6a137983d9e453f85d1ce6ca8a52cec5d718c77aba4cd8ab0974c914547998245351749d11d1842134f0a9909eb"),
    ("bbc2c9d0d7dee5ecf3fa01080f161d242b323940474e555c636a71787f868d94", "6b7885929facb9c6d3e0edfa0714212e3b4855626f7c8996", "06070a0f161f2a3746576a7f96afcae706274a6f96bfea174677aadf164f8ac7", "65ccf1bcdebeb03dec070113aac11cca2f14cd131b4516c19908b65a5661f57f95a098799e1d3363e1d7a3e41d3de1c5"),
    ("dae1e8eff6fd040b121920272e353c434a51585f666d747b828990979ea5acb3", "7c8996a3b0bdcad7e4f1fe0b1825323f4c596673808d9aa7", "07080b1017202b3847586b8097b0cbe807284b7097c0eb184778abe017508bc807", "9ee0f3fcca4af4315212142191587a01497337031b8e9bc7a1b767b5d8277ede138210c19f15a5b3fb360a2ed65b6ab95e"),
    ("f900070e151c232a31383f464d545b626970777e858c939aa1a8afb6bdc4cbd2", "8d9aa7b4c1cedbe8f5020f1c293643505d6a7784919eabb8", "08090c1118212c3948596c8198b1cce908294c7198c1ec194879ace118518cc908498cd11861acf94899ec4198f14ca90869cc3198016cd948b92ca118910c", "9d5debc3fd7ba96dbf7fd87c63c06768421bb219c09671a295d82a8f24cf7f8704fc503cfd4f7b26c3619e15e0c7f850692ab971d4a5704096cd48d25b9ca4531311bf7838b339e253166c935631b9"),
    ("181f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1", "9eabb8c5d2dfecf90613202d3a4754616e7b8895a2afbcc9", "090a0d1219222d3a495a6d8299b2cdea092a4d7299c2ed1a497aade219528dca094a8dd21962adfa499aed4299f24daa096acd3299026dda49ba2da219920d8a", "66a3abfae55a416e9f756f0337327163e88acaa766ed98dbde7536529ab2ac0d55007209d2759d33792c64b228f428b4549411a5242d1bdd25573cf6c2be737c2c5d10beff88d9f14310f7cc7db44239"),
    ("373e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb020910", "afbcc9d6e3f0fd0a1724313e4b5865727f8c99a6b3c0cdda", "0a0b0e131a232e3b4a5b6e839ab3ceeb0a2b4e739ac3ee1b4a7baee31a538ecb0a4b8ed31a63aefb4a9bee439af34eab0a6bce339a036edb4abb2ea31a930e8b0a", "b370bdaae63157b135d34f18e8df9909f3b331b8a71dc1f3a5616a561eb00f289a5253bec5e5f59439c564368c1e2931e8268ae8f75a9b6fa71aefd08f0b20fe73b9bc8bf570fe4ab1e49274d4e5a58dac"),
    ("565d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f0f7fe050c131a21282f", "c0cddae7f4010e1b2835424f5c697683909daab7c4d1deeb", "0b0c0f141b242f3c4b5c6f849bb4cfec0b2c4f749bc4ef1c4b7cafe41b548fcc0b4c8fd41b64affc4b9cef449bf44fac0b6ccf349b046fdc4bbc2fa41b940f8c0b8c0f941ba42fbc4bdc6f049b34cf6c0bac4ff49b44ef9c4bfcaf641bd48f4c0bcc8f541be4af7c4b1cefc49b744f2c0beccfb49b846f5c4b3c2f241b140f0c0b0c0f141b242f3c4b5c6f849bb4cfec0b2c4f749bc4ef1c4b7cafe41b548fcc0b4c8fd41b64affc4b9cef449bf44fac0b6ccf349b046fdc4bbc2fa41b940f8c0b8c0f941ba42fbc", "463fbec3b6dba775bfde8fdc05584366e88719891b277ca36e114bdbbfc12e2646b7e22ed790d1814d5f0fde53c869ca303890a253fa161ca97811f2e61f455df3f1618bcb399cff6d889f9d2de28f0ebd9cd234a1666f34cb4c7b6f6b6b8cd769f2204f27f4a37711d56671f7694ff1d886642cb18d53f352cb62435665f702ccdb8120a963ad61ad95356d8da0f8802c3854a81d93052c5ee7d98bb087286fb6dd5097d284ddea16995ef2a299f9d63dfe5646390368a12ea9beffc048b522abc5eb4848fbd6f84cc3decb20f9439c5827d51cf074452f"),
]
// swiftlint:enable line_length

private func bytes(_ hex: String) -> Data {
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        // Векторы выше — наш же литерал: невалидный hex — опечатка в тесте.
        data.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return data
}

@Suite("XSalsa20-Poly1305 (secretbox)")
struct SecretBoxTests {
    @Test("открывает то, что запечатал эталон, на всех длинах")
    func reference() {
        for vector in vectors {
            let opened = SecretBox.open(bytes(vector.box), nonce: bytes(vector.nonce), key: bytes(vector.key))
            #expect(opened == bytes(vector.plain), "длина \(vector.plain.count / 2)")
        }
    }

    @Test("любой изменённый байт бокса — отказ, а не мусор")
    func tamper() {
        let vector = vectors[vectors.count - 1]
        let box = bytes(vector.box)
        for position in [0, 15, 16, box.count - 1] {
            var broken = box
            broken[position] ^= 0x01
            #expect(SecretBox.open(broken, nonce: bytes(vector.nonce), key: bytes(vector.key)) == nil)
        }
    }

    @Test("чужой ключ или nonce — отказ")
    func wrongKey() {
        let vector = vectors[3]
        var key = bytes(vector.key)
        key[0] ^= 0x80
        #expect(SecretBox.open(bytes(vector.box), nonce: bytes(vector.nonce), key: key) == nil)
        var nonce = bytes(vector.nonce)
        nonce[23] ^= 0x01
        #expect(SecretBox.open(bytes(vector.box), nonce: nonce, key: bytes(vector.key)) == nil)
    }

    @Test("короткий бокс и ключ не той длины не роняют")
    func malformed() {
        #expect(SecretBox.open(Data(count: 15), nonce: Data(count: 24), key: Data(count: 32)) == nil)
        #expect(SecretBox.open(Data(count: 32), nonce: Data(count: 24), key: Data(count: 31)) == nil)
        #expect(SecretBox.open(Data(count: 32), nonce: Data(count: 23), key: Data(count: 32)) == nil)
    }
}
