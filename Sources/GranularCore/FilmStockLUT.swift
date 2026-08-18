import Foundation

struct FilmStockCube: Sendable {
    let dimension: Int
    let data: Data
}

enum FilmStockLUTLoader {
    static func load(_ stock: FilmStockID) throws -> FilmStockCube {
        guard let resourceName = stock.resourceName else {
            throw FilmRendererError.filmStockUnavailable(stock.name)
        }
        guard let url = resourceURL(named: resourceName) else {
            throw FilmRendererError.filmStockUnavailable(stock.name)
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        var dimension: Int?
        var rgba: [Float] = []

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("LUT_3D_SIZE") {
                let fields = line.split(whereSeparator: \.isWhitespace)
                if fields.count == 2 {
                    dimension = Int(fields[1])
                    if let dimension {
                        rgba.reserveCapacity(dimension * dimension * dimension * 4)
                    }
                }
                continue
            }

            guard let first = line.first, first.isNumber || first == "-" || first == "." else {
                continue
            }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3,
                  let red = Float(fields[0]),
                  let green = Float(fields[1]),
                  let blue = Float(fields[2]) else {
                throw FilmRendererError.filmStockMalformed(stock.name)
            }
            rgba.append(contentsOf: [red, green, blue, 1])
        }

        guard let dimension,
              dimension > 1,
              rgba.count == dimension * dimension * dimension * 4 else {
            throw FilmRendererError.filmStockMalformed(stock.name)
        }

        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return FilmStockCube(dimension: dimension, data: data)
    }

    private static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(
            forResource: name,
            withExtension: "cube",
            subdirectory: "FilmStocks"
        ) ?? Bundle.module.url(
            forResource: name,
            withExtension: "cube",
            subdirectory: "FilmStocks"
        )
    }
}
