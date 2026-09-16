import Testing
import Foundation
@testable import YT_Music

@Suite("Network proxy")
struct NetworkSessionTests {
    @Test("Parses HTTP proxy host and port")
    func parsesProxy() {
        let proxy = NetworkProxy(string: " http://localhost:8888 ")

        #expect(proxy?.host == "localhost")
        #expect(proxy?.port == 8888)
        #expect(proxy?.connectionProxyDictionary["HTTPProxy"] as? String == "localhost")
        #expect(proxy?.connectionProxyDictionary["HTTPSPort"] as? Int == 8888)
    }

    @Test("Rejects unsupported or malformed proxy URLs")
    func rejectsInvalidProxy() {
        #expect(NetworkProxy(string: "") == nil)
        #expect(NetworkProxy(string: "socks5://localhost:1080") == nil)
        #expect(NetworkProxy(string: "localhost:8888") == nil)
    }
}
