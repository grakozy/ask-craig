import Foundation

class OllamaService {
    private let session: URLSession

    // Persisted selected model
    private(set) var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "CraigSelectedModel") }
    }

    private var maxTokens: Int = 256
    private var temperature: Double = 0.2
    private var topP: Double = 0.9

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.selectedModel = UserDefaults.standard.string(forKey: "CraigSelectedModel") ?? "llama3.2:1b-instruct-q4_K_M"
        if let t = UserDefaults.standard.object(forKey: "CraigTemperature") as? Double { self.temperature = t }
        if let p = UserDefaults.standard.object(forKey: "CraigTopP") as? Double { self.topP = p }
        if let m = UserDefaults.standard.object(forKey: "CraigMaxTokens") as? Int { self.maxTokens = m }
    }

    func checkStatus(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { completion(false); return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let task = session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse { completion(httpResponse.statusCode == 200) } else { completion(false) }
        }
        task.resume()
    }

    struct OllamaTag: Decodable { let name: String }
    struct TagsResponse: Decodable { let models: [OllamaTag]? }

    func listModels(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1))); return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "No data", code: -1))); return }
            if let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data), let models = decoded.models?.map({ $0.name }) {
                completion(.success(models)); return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let models = json["models"] as? [[String: Any]] {
                    let names = models.compactMap { $0["name"] as? String }
                    completion(.success(names))
                } else {
                    completion(.failure(NSError(domain: "Invalid response", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected tags schema"])))
                }
            } catch { completion(.failure(error)) }
        }
        task.resume()
    }

    func setSelectedModel(_ name: String) { self.selectedModel = name }

    func setOptions(maxTokens: Int?, temperature: Double?, topP: Double?) {
        if let m = maxTokens { self.maxTokens = m; UserDefaults.standard.set(m, forKey: "CraigMaxTokens") }
        if let t = temperature { self.temperature = t; UserDefaults.standard.set(t, forKey: "CraigTemperature") }
        if let p = topP { self.topP = p; UserDefaults.standard.set(p, forKey: "CraigTopP") }
    }

    func ask(question: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1))); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let body: [String: Any] = [
            "model": selectedModel,
            "prompt": question,
            "stream": false,
            "options": [
                "temperature": temperature,
                "top_p": topP,
                "num_predict": maxTokens
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "No data", code: -1))); return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let response = json["response"] as? String { completion(.success(response)); return }
                    if let errorMsg = json["error"] as? String { completion(.failure(NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))); return }
                }
                completion(.failure(NSError(domain: "Invalid response", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected generate schema"])))
            } catch { completion(.failure(error)) }
        }
        task.resume()
    }

    func askStream(question: String,
                   onToken: @escaping (String) -> Void,
                   onError: @escaping (Error) -> Void,
                   onComplete: @escaping () -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { onError(NSError(domain: "Invalid URL", code: -1)); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let body: [String: Any] = [
            "model": selectedModel,
            "prompt": question,
            "stream": true,
            "options": [
                "temperature": temperature,
                "top_p": topP,
                "num_predict": maxTokens
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        class StreamDelegate: NSObject, URLSessionDataDelegate {
            let onToken: (String) -> Void
            let onError: (Error) -> Void
            let onComplete: () -> Void
            var buffer = Data()
            init(onToken: @escaping (String) -> Void, onError: @escaping (Error) -> Void, onComplete: @escaping () -> Void) {
                self.onToken = onToken; self.onError = onError; self.onComplete = onComplete
            }
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                buffer.append(data)
                while let range = buffer.firstRange(of: Data("\n".utf8)) {
                    let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                    guard !line.isEmpty else { continue }
                    if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        if let done = obj["done"] as? Bool, done == true { onComplete(); return }
                        if let token = obj["response"] as? String { onToken(token) }
                        if let err = obj["error"] as? String { onError(NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: err])) }
                    }
                }
            }
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error = error { onError(error) } else { onComplete() }
            }
        }

        let delegate = StreamDelegate(onToken: onToken, onError: onError, onComplete: onComplete)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
    }
}
