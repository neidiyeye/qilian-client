import Foundation

// DbaoJSON 只做 JSON 对象校验和序列化，不解析或记录节点凭据。
public enum DbaoJSON {
    public static func object(from value: Any) throws -> [String: Any] {
        guard let object = value as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else {
            throw DbaoTunnelError.invalidPayload
        }
        return object
    }

    public static func data(from object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw DbaoTunnelError.invalidPayload
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func object(from data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw DbaoTunnelError.invalidPayload
        }
        return object
    }

    public static func string(from object: [String: Any]) throws -> String {
        let data = try data(from: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DbaoTunnelError.invalidPayload
        }
        return text
    }
}
