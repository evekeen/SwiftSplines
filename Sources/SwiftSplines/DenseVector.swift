
import Accelerate
import Foundation

struct DenseVector {
    let values: [Double]

    func use(calculate: (DenseVector_Double) -> Void) {
        var mutableValues = self.values
        mutableValues.withUnsafeMutableBufferPointer { valuePtr in
            let vector = DenseVector_Double(
                count: Int32(values.count),
                data: valuePtr.baseAddress!
            )
            calculate(vector)
        }
    }
}

extension DenseVector {
    
    static func cubicSpline<P: DataPoint>(
        points: [P.Scalar],
        boundaryCondition: Spline<P>.BoundaryCondition,
        dimension: Int
    ) -> DenseVector {
        let y = points.map { $0.asDouble }
        let values = (0 ..< points.count).map { (index) -> Double in
            if index == 0 {
                switch boundaryCondition {
                case .circular:
                    return 3 * (y[1] - y.last!)
                case .fixedTangentials(let dAtStart, _):
                    return dAtStart[dimension].asDouble
                case .smooth:
                    return 3 * (y[1] - y[0])
                }
            } else if index == points.count - 1 {
                switch boundaryCondition {
                case .circular:
                    return 3 * (y[0] - y[index-1])
                case .fixedTangentials(_, let dAtEnd):
                    return dAtEnd[dimension].asDouble
                case .smooth:
                    return 3 * (y[index] - y[index-1])
                }
            } else {
                return 3 * (y[index+1] - y[index-1])
            }
        }
        return DenseVector(values: values)
    }
    
}