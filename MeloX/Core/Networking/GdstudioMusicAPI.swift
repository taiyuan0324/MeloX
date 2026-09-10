import Foundation

// MARK: - Gdstudio Music API Client
//
// This client communicates with the third-party music API at
// https://music-api.gdstudio.xyz/api.php
//
// Supported endpoints:
//   - Search:      ?types=search&source=netease&name=<keywords>&count=<limit>&pages=<page>
//   - Song URL:    ?types=url&source=netease&id=<track_id>&br=<128|192|320|740|999>
//   - Lyrics:      ?types=lyric&source=netease&id=<lyric_id>
//   - Album Pic:   ?types=pic&source=netease&id=<pic_id>&size=<300|500>

@MainActor
final class GdstudioMusicAPI {
    static let baseURL = URL(string: "https://music-api.gdstudio.xyz/api.php")!
    
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Response Models
    
    struct SearchResult: Decodable {
        let id: String
        let name: String
        let artist: String?
        let album: String?
        let picID: String?
        let urlID: String?
        let lyricID: String?
        let source: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name, artist, album
            case picID = "pic_id"
            case urlID = "url_id"
            case lyricID = "lyric_id"
            case source
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            artist = try container.decodeIfPresent(String.self, forKey: .artist)
            album = try container.decodeIfPresent(String.self, forKey: .album)
            picID = try container.decodeIfPresent(String.self, forKey: .picID)
            urlID = try container.decodeIfPresent(String.self, forKey: .urlID)
            lyricID = try container.decodeIfPresent(String.self, forKey: .lyricID)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            
            // id can be a String or an Int in the API response
            if let stringID = try? container.decode(String.self, forKey: .id) {
                id = stringID
            } else if let intID = try? container.decode(Int.self, forKey: .id) {
                id = String(intID)
            } else {
                id = ""
            }
        }
    }
    
    struct SongURLResult: Decodable {
        let url: String?
        let br: Int?
        let size: Int?
        
        enum CodingKeys: String, CodingKey {
            case url, br, size
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            
            // br can be a String or Int in the API response
            if let intBR = try? container.decode(Int.self, forKey: .br) {
                br = intBR
            } else if let stringBR = try? container.decode(String.self, forKey: .br),
                      let parsedBR = Int(stringBR) {
                br = parsedBR
            } else {
                br = nil
            }
            
            // size can be a String or Int in the API response
            if let intSize = try? container.decode(Int.self, forKey: .size) {
                size = intSize
            } else if let stringSize = try? container.decode(String.self, forKey: .size),
                      let parsedSize = Int(stringSize) {
                size = parsedSize
            } else {
                size = nil
            }
        }
    }
    
    struct LyricResult: Decodable {
        let lyric: String?
        let tlyric: String?
    }
    
    // MARK: - API Methods
    
    /// Search for songs on the specified music source.
    func search(
        name: String,
        source: String = "netease",
        count: Int = 30,
        pages: Int = 1
    ) async throws -> [SearchResult] {
        var components = URLComponents(
            string: Self.baseURL.absoluteString
        )!
        components.queryItems = [
            URLQueryItem(name: "types", value: "search"),
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "pages", value: String(pages)),
        ]
        guard let url = components.url else {
            throw APIError.requestEncoding
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("MeloX/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        guard !data.isEmpty else {
            throw APIError.emptyResponse(statusCode: httpResponse.statusCode)
        }
        
        // The API may return either an array or an object with an array inside.
        // Try array first, then fallback to object.
        if let results = try? JSONDecoder().decode([SearchResult].self, from: data) {
            return results
        }
        
        struct SearchResponse: Decodable {
            let data: [SearchResult]?
            let songs: [SearchResult]?
            let results: [SearchResult]?
        }
        
        if let wrapper = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return wrapper.data ?? wrapper.songs ?? wrapper.results ?? []
        }
        
        throw APIError.invalidResponse
    }
    
    /// Get the playable audio URL for a track.
    func songURL(
        id: String,
        source: String = "netease",
        br: Int = 320
    ) async throws -> SongURLResult {
        var components = URLComponents(
            string: Self.baseURL.absoluteString
        )!
        components.queryItems = [
            URLQueryItem(name: "types", value: "url"),
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "br", value: String(br)),
        ]
        guard let url = components.url else {
            throw APIError.requestEncoding
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("MeloX/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        guard !data.isEmpty else {
            throw APIError.emptyResponse(statusCode: httpResponse.statusCode)
        }
        
        // The API may return the result directly or wrapped in an object.
        if let result = try? JSONDecoder().decode(SongURLResult.self, from: data) {
            return result
        }
        
        struct URLResponse: Decodable {
            let data: SongURLResult?
        }
        
        if let wrapper = try? JSONDecoder().decode(URLResponse.self, from: data) {
            if let result = wrapper.data {
                return result
            }
        }
        
        throw APIError.invalidResponse
    }
    
    /// Get lyrics for a track.
    func lyrics(
        id: String,
        source: String = "netease"
    ) async throws -> LyricResult {
        var components = URLComponents(
            string: Self.baseURL.absoluteString
        )!
        components.queryItems = [
            URLQueryItem(name: "types", value: "lyric"),
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "id", value: id),
        ]
        guard let url = components.url else {
            throw APIError.requestEncoding
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("MeloX/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        guard !data.isEmpty else {
            throw APIError.emptyResponse(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(LyricResult.self, from: data)
    }
}
