// Copyright (c) 2020 mathHeartCode UG(haftungsbeschränkt) <konrad@mathheartcode.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

public struct Spline<P: DataPoint> {
    
    /// To get the appropriate number of equations
    /// we need some kind of boundary condition
    /// - fixedTangentials: fixes the first derivative for both ends
    /// - smooth: fixes the second derivative to be zero at the ends
    /// - circular: derivative is the same at both ends
    public enum BoundaryCondition {
        case fixedTangentials(dAtStart: P, dAtEnd: P)
        case smooth
        case circular
    }
        
    /// Create a cubic piece wise spline based on the provided input
    /// - Parameters:
    ///   - values: The control values the spline will intercept
    ///   - arguments: optionally, the arguments at the control points t_0 .. t_n can be supplied,
    ///    by default they are 0 ... n
    ///   - boundaryCondition: the chosen `BoundaryCondition`
    public init(
        arguments: [P.Scalar]? = nil,
        values: [P],
        boundaryCondition: BoundaryCondition = .smooth
    ) {
        if let arguments = arguments, arguments.count != values.count {
            fatalError("Length of values and arguments arrays don't match, \(values.count) != \(arguments.count)")
        }
                
        let args = arguments ?? values.enumerated().map({ P.Scalar($0.0) })
        self.init(
            arguments: args,
            values: values,
            derivatives: Self.computeDerivatives(from: values, boundaryCondition: boundaryCondition),
            boundaryCondition: boundaryCondition
        )
    }
    
    /// In cases where y(t_n) and the derivative y'(t_n) is known for all points
    /// use this initializer
    /// - Parameter points: the control points
    /// - Parameter derivatives: f'(t) at the control points
    public init(
        arguments: [P.Scalar],
        values: [P],
        derivatives: [P],
        boundaryCondition: BoundaryCondition = .smooth
    ) {
        guard values.count == derivatives.count && values.count == arguments.count else {
            fatalError("The number of control points needs to be equal lentgh to the number of derivatives")
        }
        guard values.count >= 2 else {
            fatalError("Can't create piece wise spline with less then 2 control points")
        }
                
        self.controlPoints = arguments
        var coefficients = Self.computeCoefficients(from: values, d: derivatives)
        if case .circular = boundaryCondition, values.count > 1 {
            coefficients.append(CubicPoly(
                p0: values.last!, p1: values.first!,
                d0: derivatives.last!, d1: derivatives.first!)
            )
        }
        self.coefficients = coefficients
        self.boundary = boundaryCondition
        self.norms = derivatives.map { p in return p.norm() }
    }
    
    /// Calculates the interpolation at a given argument
    /// - Parameter t: the argument provided
    /// - Returns: The interpolation calculated by finding the cubic spline segment and then calculating the cubic function of scaled t
    public func f(t: P.Scalar) -> P {
        guard t >= controlPoints[0] else {
            switch boundary {
            case .circular:
                let negative = controlPoints[0] - t
                if negative <= 1 {
                    return coefficients[controlPoints.count-1].f(t: 1 - negative)
                } else {
                    let factor = ceil(negative/length)
                    let tNew = t + factor * length
                    return f(t: tNew)
                }
            case .fixedTangentials(let dAtStart, _):
                // extend linear function to the left
                let negative = controlPoints[0] - t
                return coefficients[0].a + (negative * dAtStart)
            case .smooth:
                let len0 = (controlPoints[1] - controlPoints[0])
                let lambda = (t - controlPoints[0]) / len0
                return coefficients[0].f(t: lambda)
            }
        }

        guard let last = controlPoints.last else { return coefficients[0].a }
        guard t != last else {
            switch boundary {
            case .circular:
                return coefficients.last!.f(t: 0)
            default:
                return coefficients.last!.f(t: 1)
            }
        }
        guard t < last else {
            // extend constant function to the right
            // extend constant function to the left
            switch boundary {
            case .circular:
                let positive = t - last
                if positive <= 1 {
                    return coefficients[controlPoints.count-1].f(t: positive)
                } else {
                    let factor = ceil(positive/length)
                    let tNew = t - factor * length
                    return f(t: tNew)
                }
            case .fixedTangentials(_, let dAtEnd):
                let value = coefficients[coefficients.count - 1].f(t: 1)
                let positive = t - last
                return value + positive * dAtEnd
            case .smooth:
                let end = controlPoints.count - 1
                let len0 = (controlPoints[end] - controlPoints[end-1])
                let lambda = (t - controlPoints[end-1]) / len0
                return coefficients[controlPoints.count-2].f(t: lambda)
            }
        }
        
        // find t_n where t_n <= t < t_n+1
        let index = controlPoints.enumerated().first(where: { (offset, element) -> Bool in
            return element <= t && offset + 1 < controlPoints.count && t < controlPoints[offset+1]
        })?.offset ?? controlPoints.count - 1
        let lambda = (t - controlPoints[index])
            / (controlPoints[index + 1] - controlPoints[index])

        return coefficients[index].f(t: lambda)
    }
    
    private let boundary: BoundaryCondition
    private let controlPoints: [P.Scalar]
    private let coefficients: [CubicPoly]
    
    public let norms: [P]

    private var length: P.Scalar {
        guard let first = controlPoints.first, let last = controlPoints.last else {
            return 0
        }
        return last - first
    }
    
    struct CubicPoly {
        init(p0: P, p1: P, d0: P, d1: P) {
            self.a = p0
            self.b = d0
            self.c = 3*(p1 - p0) - 2*d0 - d1
            self.d = 2*(p0 - p1) + d0 + d1
        }
        
        let a, b, c, d: P
    }
}

private extension Spline.CubicPoly {
    
    /// Piecewise function
    /// - Parameter t: input value between 0 and 1
    func f(t: P.Scalar) -> P {
        let t2 = t * t
        let linear: P = a + (t * b)
        let quadratic: P = (t2 * c)
        return linear + quadratic + (t2 * t * d)
    }
}
