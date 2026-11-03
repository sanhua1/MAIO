@testable import FeatureTranslate
import Foundation
import Testing

struct KeyedProviderSigningTests {
    /// 官方文档示例：appid 2015063000000001、q apple、salt 1435660288、密钥 12345678
    @Test func `baidu sign matches official example`() {
        let sign = BaiduProvider.sign(appID: "2015063000000001", text: "apple", salt: "1435660288", secret: "12345678")
        #expect(sign == "f89f9594663708c1605f3d736d01d2d4")
    }

    @Test func `youdao truncates long input`() {
        #expect(YoudaoProvider.truncate("short text") == "short text")
        #expect(YoudaoProvider.truncate("Hello, this is a long sentence for youdao.") == "Hello, thi42or youdao.")
        #expect(YoudaoProvider.truncate("一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子") == "一二三四五六七八九十21乙丙丁戊己庚辛壬癸子")
    }

    /// 期望值由 Python hashlib 按官方 v3 规则独立算出
    @Test func `youdao sign V 3`() {
        let sign = YoudaoProvider.sign(
            appKey: "appk", text: "Hello, this is a long sentence for youdao.", salt: "salt1",
            curtime: "1700000000", appSecret: "secr",
        )
        #expect(sign == "48598b4f1e80e1f36d46fdac7ebd7b362f8da3288e588ff71e2c1492442c261b")
    }

    /// 官方文档（https://cloud.tencent.com/document/api/551/30636）的 CVM 示例
    @Test func `tencent canonical request matches official example`() {
        let payload = #"{"Limit": 1, "Filters": [{"Values": ["\u672a\u547d\u540d"], "Name": "instance-name"}]}"#
        let signing = TencentSigning(
            host: "cvm.tencentcloudapi.com", service: "cvm", action: "DescribeInstances",
            contentType: "application/json; charset=utf-8", payload: Data(payload.utf8), timestamp: 1_551_113_065,
        )
        #expect(signing.date == "2019-02-25")
        #expect(Crypto.sha256Hex(Data(payload.utf8)) == "35e9c5b0e3ae67532d3c9f17ead6c90222632e5b1ff7f6e89887f1398934f064")
        #expect(Crypto.sha256Hex(signing.canonicalRequest) == "7019a55be8395899b900fb5564e4200d984910f34794a27cb3fb7d10ff6a1e84")
        // 官方示例的密钥被打码，签名期望值由 Python hmac 按同样步骤独立算出
        let authorization = signing.authorization(secretID: "AKIDEXAMPLE", secretKey: "Gu5t9xGARNpq86cd98joQYCN3EXAMPLE")
        #expect(authorization == "TC3-HMAC-SHA256 Credential=AKIDEXAMPLE/2019-02-25/cvm/tc3_request, "
            + "SignedHeaders=content-type;host;x-tc-action, "
            + "Signature=644be983de9a8a3f00db8eadaba61467c3b429e2215758ba897b738ca469fd26")
    }

    /// 官方文档「RPC 风格签名」示例：testid / testsecret，DescribeRegions
    @Test func `alibaba signature matches official example`() {
        let parameters = [
            ("Version", "2014-05-26"), ("Action", "DescribeRegions"), ("AccessKeyId", "testid"),
            ("Format", "XML"), ("SignatureMethod", "HMAC-SHA1"),
            ("SignatureNonce", "3ee8c1b8-83d3-44af-a94f-4e0ad82fd6cf"), ("SignatureVersion", "1.0"),
            ("Timestamp", "2016-02-23T12:46:24Z"),
        ]
        #expect(AlibabaProvider.stringToSign(method: "GET", parameters: parameters).hasPrefix(
            "GET&%2F&AccessKeyId%3Dtestid%26Action%3DDescribeRegions%26Format%3DXML",
        ))
        #expect(AlibabaProvider.signature(method: "GET", parameters: parameters, secret: "testsecret")
            == "OLeaidS1JvxuMvnyHOwuJ+uX5qY=")
    }

    @Test func `alibaba encodes special characters`() {
        let toSign = AlibabaProvider.stringToSign(method: "POST", parameters: [("SourceText", "a b*~")])
        #expect(toSign == "POST&%2F&SourceText%3Da%2520b%252A~")
    }

    /// 期望值由 Python hmac 按官方签名步骤独立算出
    @Test func `volcengine signature`() {
        let signing = VolcengineSigning(
            host: "translate.volcengineapi.com", query: VolcengineProvider.query,
            payload: Data(#"{"TargetLanguage":"zh","TextList":["hello"]}"#.utf8),
            date: Date(timeIntervalSince1970: 1_704_067_200),
        )
        #expect(signing.timestamp == "20240101T000000Z")
        #expect(signing.credentialScope == "20240101/cn-north-1/translate/request")
        #expect(signing.signature(secret: "testsecret") == "62d0880eb398b1203079c11e2608174c5b6200b6d195ae3e166484afb21f3daf")
    }

    @Test func `deep L endpoint depends on key suffix`() {
        #expect(DeepLProvider.endpoint(authKey: "abc:fx") == "https://api-free.deepl.com")
        #expect(DeepLProvider.endpoint(authKey: "abc") == "https://api.deepl.com")
    }
}

struct KeyedProviderLanguageTests {
    @Test func `baidu uses its own codes`() {
        #expect(BaiduProvider.code(.japanese) == "jp")
        #expect(BaiduProvider.code(.traditionalChinese) == "cht")
        #expect(BaiduProvider.code(.arabic) == "ara")
        #expect(BaiduProvider.code(.auto) == "auto")
    }

    @Test func `youdao uses CHS codes`() {
        #expect(YoudaoProvider.code(.simplifiedChinese) == "zh-CHS")
        #expect(YoudaoProvider.code(.traditionalChinese) == "zh-CHT")
        #expect(YoudaoProvider.code(.japanese) == "ja")
    }

    @Test func `tencent rejects unsupported languages`() {
        #expect(TencentProvider.code(.traditionalChinese) == "zh-TW")
        #expect(TencentProvider.code(.dutch) == nil)
    }

    @Test func `deep L distinguishes source and target`() {
        #expect(DeepLProvider.code(.simplifiedChinese) == "ZH-HANS")
        #expect(DeepLProvider.sourceCode(.simplifiedChinese) == "ZH")
        #expect(DeepLProvider.code(.english) == "EN-US")
        #expect(DeepLProvider.sourceCode(.english) == "EN")
        #expect(DeepLProvider.code(.thai) == nil)
        #expect(DeepLProvider.sourceCode(.auto) == nil)
    }

    @Test func `other provider codes`() {
        #expect(AlibabaProvider.code(.traditionalChinese) == "zh-tw")
        #expect(VolcengineProvider.code(.traditionalChinese) == "zh-Hant")
        #expect(NiutransProvider.code(.traditionalChinese) == "cht")
        #expect(CaiyunProvider.code(.traditionalChinese) == "zh-Hant")
        #expect(CaiyunProvider.code(.thai) == nil)
    }

    /// 每个源都至少支持中英互译
    @Test func `every provider supports chinese and english`() {
        let maps: [(Language) -> String?] = [
            BaiduProvider.code, YoudaoProvider.code, TencentProvider.code, AlibabaProvider.code,
            VolcengineProvider.code, CaiyunProvider.code, NiutransProvider.code, DeepLProvider.code,
        ]
        for map in maps {
            #expect(map(.simplifiedChinese) != nil)
            #expect(map(.english) != nil)
        }
    }

    @Test func `caiyun rejects unsupported target`() async {
        let provider = CaiyunProvider(token: "t", http: HTTPClient())
        let request = TranslationRequest(text: "hi", source: .auto, target: .french)
        await #expect(throws: TranslationError.unsupportedLanguage(.french)) {
            try await provider.translate(request) { _ in }
        }
    }

    @Test func `deep L without key or URL asks for key`() async {
        let provider = DeepLProvider(authKey: "", customURL: "", http: HTTPClient())
        let request = TranslationRequest(text: "hi", source: .auto, target: .english)
        await #expect(throws: TranslationError.missingSecret("Auth Key")) {
            try await provider.translate(request) { _ in }
        }
    }

    @Test func `factory builds every keyed provider`() throws {
        let keyed: [ProviderKind] = [.deepl, .baidu, .youdao, .tencent, .alibaba, .volcengine, .caiyun, .niutrans]
        for kind in keyed {
            _ = try KeyedProviders.make(kind, values: [:], http: HTTPClient())
        }
        #expect(throws: TranslationError.self) { try KeyedProviders.make(.google, values: [:], http: HTTPClient()) }
    }
}
