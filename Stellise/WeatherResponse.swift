import Foundation

// APIレスポンス全体
struct WeatherResponse: Decodable {
    let main: MainWeather
    let weather: [WeatherDescription]
    let coord: Coordinates
    
    // ★★★ この Sys 構造体を追加 ★★★
    // "sys": { "sunrise": 1668808215, "sunset": 1668846763 }
    let sys: Sys
}

struct MainWeather: Decodable {
    let temp: Double
    let feels_like: Double
}

struct WeatherDescription: Decodable {
    let main: String
    let description: String
    let icon: String
}

struct Coordinates: Decodable {
    let lon: Double
    let lat: Double
}

// ★★★ この Sys 構造体を追加 ★★★
// (日の出・日の入り時刻を UNIX タイムスタンプ [秒] として受け取る)
struct Sys: Decodable {
    let sunrise: TimeInterval // UNIXタイムスタンプ (例: 1731526800)
    let sunset: TimeInterval  // UNIXタイムスタンプ
}
