    public func compensatedAdd(_ sum: inout Double, _ compensation: inout Double, _ value: Double) {
        let next = sum + value
        compensation += abs(sum) >= abs(value) ? ((sum - next) + value) : ((value - next) + sum)
        sum = next
    }
