/// Fixed-capacity buffer that overwrites its oldest element when full.
///
/// Every buffer in the app is bounded on purpose: an unbounded one is a leak
/// with a delayed due date. Storage is allocated once and never grows.
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    private var storage: [Element?]
    private var head = 0
    public private(set) var count = 0

    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    public var isEmpty: Bool { count < 1 }
    public var isFull: Bool { count == capacity }

    /// Appends an element, dropping the oldest one when at capacity.
    public mutating func append(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Elements from oldest to newest.
    public var elements: [Element] {
        guard !isEmpty else { return [] }
        var result = [Element]()
        result.reserveCapacity(count)
        let start = (head - count + capacity) % capacity
        for offset in 0..<count {
            if let value = storage[(start + offset) % capacity] { result.append(value) }
        }
        return result
    }

    /// The most recent element, if any.
    public var last: Element? {
        guard !isEmpty else { return nil }
        return storage[(head - 1 + capacity) % capacity]
    }

    public mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }
}
