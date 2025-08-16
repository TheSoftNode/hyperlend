// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Math
 * @dev Advanced mathematical operations library optimized for DeFi calculations
 * @notice Gas-optimized implementations for high-frequency operations on Somnia
 */
library Math {
    // ═══════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant HALF_PRECISION = 5e17;

    // ═══════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    error Math__DivisionByZero();
    error Math__Overflow();
    error Math__InvalidInput();

    // ═══════════════════════════════════════════════════════════════════════════════════
    // CORE MATH FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Multiply two numbers and divide by a third, with overflow protection
     * @param a First number
     * @param b Second number
     * @param c Divisor
     * @return result (a * b) / c
     */
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256 result) {
        if (c == 0) revert Math__DivisionByZero();

        // Handle overflow for large numbers
        if (a == 0 || b == 0) return 0;

        // Check for overflow in multiplication
        uint256 prod = a * b;
        if (prod / a != b) {
            // Use assembly for high precision calculation when overflow would occur
            assembly {
                let mm := mulmod(a, b, not(0))
                prod := div(prod, c)
                if mm {
                    let remainder := mulmod(a, b, c)
                    if iszero(gt(remainder, div(sub(0, 1), 2))) {
                        result := add(prod, div(mm, c))
                    }
                    if gt(remainder, div(sub(0, 1), 2)) {
                        result := add(prod, add(div(mm, c), 1))
                    }
                }
                if iszero(mm) {
                    result := prod
                }
            }
        } else {
            result = prod / c;
        }
    }

    /**
     * @notice Multiply two numbers with precision scaling
     * @param a First number (scaled)
     * @param b Second number (scaled)
     * @return result (a * b) / PRECISION
     */
    function mulWad(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256 result) {
        return mulDiv(a, b, PRECISION);
    }

    /**
     * @notice Divide two numbers with precision scaling
     * @param a Dividend (scaled)
     * @param b Divisor (scaled)
     * @return result (a * PRECISION) / b
     */
    function divWad(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256 result) {
        return mulDiv(a, PRECISION, b);
    }

    /**
     * @notice Calculate square root using Newton's method
     * @param x Input number
     * @return result Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;

        // Initial guess
        uint256 z = (x + 1) / 2;
        result = x;

        // Newton's method iteration
        while (z < result) {
            result = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice Calculate power using exponentiation by squaring
     * @param base Base number
     * @param exponent Exponent
     * @return result base^exponent
     */
    function pow(
        uint256 base,
        uint256 exponent
    ) internal pure returns (uint256 result) {
        if (exponent == 0) return PRECISION;
        if (base == 0) return 0;

        result = PRECISION;
        uint256 currentBase = base;

        while (exponent > 0) {
            if (exponent & 1 == 1) {
                result = mulWad(result, currentBase);
            }
            currentBase = mulWad(currentBase, currentBase);
            exponent >>= 1;
        }
    }

    /**
     * @notice Calculate natural logarithm (ln) using Taylor series
     * @param x Input (scaled by PRECISION)
     * @return result ln(x) scaled by PRECISION
     */
    function ln(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) revert Math__InvalidInput();
        if (x == PRECISION) return 0;

        // Use change of variables: ln(x) = ln(1 + (x-1))
        // For better convergence, use ln(x) = 2 * artanh((x-1)/(x+1))

        if (x < PRECISION) {
            // For x < 1, use ln(x) = -ln(1/x)
            return ln(divWad(PRECISION, x));
        }

        // Rough approximation for large numbers
        uint256 power = 0;
        uint256 temp = x;

        // Reduce x to manageable range
        while (temp >= 2 * PRECISION) {
            temp = temp / 2;
            power++;
        }

        // Taylor series approximation for ln(1 + z) where z = (temp - 1)
        uint256 z = temp - PRECISION;
        uint256 term = z;
        result = term;

        // Add terms: z - z^2/2 + z^3/3 - z^4/4 + ...
        for (uint256 i = 2; i <= 10; i++) {
            term = mulWad(term, z);
            if (i & 1 == 0) {
                result -= term / i;
            } else {
                result += term / i;
            }
        }

        // Add back the power of 2 reduction: ln(2^power * y) = power * ln(2) + ln(y)
        result += power * 693147180559945309; // ln(2) scaled by PRECISION
    }

    /**
     * @notice Calculate exponential function (e^x)
     * @param x Input (scaled by PRECISION)
     * @return result e^x scaled by PRECISION
     */
    function exp(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return PRECISION;

        // Use Taylor series: e^x = 1 + x + x^2/2! + x^3/3! + ...
        // For large x, use e^x = e^(a+b) = e^a * e^b where a is integer part

        uint256 integer_part = x / PRECISION;
        uint256 fractional_part = x % PRECISION;

        // Calculate e^fractional_part using Taylor series
        result = PRECISION; // Start with 1
        uint256 term = fractional_part;

        for (uint256 i = 1; i <= 15; i++) {
            result += term / factorial(i);
            term = mulWad(term, fractional_part);
        }

        // Multiply by e^integer_part = e^1 raised to integer_part power
        if (integer_part > 0) {
            uint256 e = 2718281828459045235; // e scaled by PRECISION
            result = mulWad(result, pow(e, integer_part));
        }
    }

    /**
     * @notice Calculate compound interest
     * @param principal Principal amount
     * @param rate Interest rate per period (scaled by PRECISION)
     * @param periods Number of periods
     * @return result Final amount after compound interest
     */
    function compoundInterest(
        uint256 principal,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256 result) {
        if (periods == 0) return principal;

        // A = P(1 + r)^n
        uint256 onePlusRate = PRECISION + rate;
        uint256 factor = pow(onePlusRate, periods);
        result = mulWad(principal, factor);
    }

    /**
     * @notice Calculate weighted average
     * @param values Array of values
     * @param weights Array of weights
     * @return result Weighted average
     */
    function weightedAverage(
        uint256[] memory values,
        uint256[] memory weights
    ) internal pure returns (uint256 result) {
        if (values.length != weights.length || values.length == 0) {
            revert Math__InvalidInput();
        }

        uint256 totalWeightedValue = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < values.length; i++) {
            totalWeightedValue += mulWad(values[i], weights[i]);
            totalWeight += weights[i];
        }

        if (totalWeight == 0) revert Math__DivisionByZero();

        result = divWad(totalWeightedValue, totalWeight);
    }

    /**
     * @notice Calculate percentage change between two values
     * @param oldValue Original value
     * @param newValue New value
     * @return result Percentage change (scaled by PRECISION)
     */
    function percentageChange(
        uint256 oldValue,
        uint256 newValue
    ) internal pure returns (int256 result) {
        if (oldValue == 0) revert Math__DivisionByZero();

        if (newValue >= oldValue) {
            result = int256(divWad(newValue - oldValue, oldValue));
        } else {
            result = -int256(divWad(oldValue - newValue, oldValue));
        }
    }

    /**
     * @notice Calculate moving average
     * @param values Array of values
     * @param windowSize Size of moving window
     * @return result Array of moving averages
     */
    function movingAverage(
        uint256[] memory values,
        uint256 windowSize
    ) internal pure returns (uint256[] memory result) {
        if (values.length < windowSize || windowSize == 0) {
            revert Math__InvalidInput();
        }

        result = new uint256[](values.length - windowSize + 1);

        for (uint256 i = 0; i <= values.length - windowSize; i++) {
            uint256 sum = 0;
            for (uint256 j = i; j < i + windowSize; j++) {
                sum += values[j];
            }
            result[i] = sum / windowSize;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate factorial (optimized for small numbers)
     * @param n Input number
     * @return result n!
     */
    function factorial(uint256 n) internal pure returns (uint256 result) {
        if (n == 0 || n == 1) return 1;
        if (n > 20) revert Math__Overflow(); // Prevent overflow

        result = 1;
        for (uint256 i = 2; i <= n; i++) {
            result *= i;
        }
    }

    /**
     * @notice Return minimum of two numbers
     * @param a First number
     * @param b Second number
     * @return result Minimum value
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a < b ? a : b;
    }

    /**
     * @notice Return maximum of two numbers
     * @param a First number
     * @param b Second number
     * @return result Maximum value
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a > b ? a : b;
    }

    /**
     * @notice Clamp value between min and max
     * @param value Value to clamp
     * @param lower Lower bound
     * @param upper Upper bound
     * @return result Clamped value
     */
    function clamp(
        uint256 value,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256 result) {
        if (lower > upper) revert Math__InvalidInput();
        result = min(max(value, lower), upper);
    }

    /**
     * @notice Calculate absolute difference between two numbers
     * @param a First number
     * @param b Second number
     * @return result |a - b|
     */
    function absDiff(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256 result) {
        result = a >= b ? a - b : b - a;
    }

    /**
     * @notice Check if two numbers are approximately equal within tolerance
     * @param a First number
     * @param b Second number
     * @param tolerance Tolerance level (scaled by PRECISION)
     * @return result True if approximately equal
     */
    function approxEqual(
        uint256 a,
        uint256 b,
        uint256 tolerance
    ) internal pure returns (bool result) {
        if (a == b) return true;

        uint256 diff = absDiff(a, b);
        uint256 maxValue = max(a, b);

        if (maxValue == 0) return diff <= tolerance;

        result = divWad(diff, maxValue) <= tolerance;
    }

    /**
     * @notice Linear interpolation between two values
     * @param a Start value
     * @param b End value
     * @param t Interpolation factor (0 to PRECISION)
     * @return result Interpolated value
     */
    function lerp(
        uint256 a,
        uint256 b,
        uint256 t
    ) internal pure returns (uint256 result) {
        if (t > PRECISION) revert Math__InvalidInput();

        if (a <= b) {
            result = a + mulWad(b - a, t);
        } else {
            result = a - mulWad(a - b, t);
        }
    }

    /**
     * @notice Calculate standard deviation of an array
     * @param values Array of values
     * @return result Standard deviation
     */
    function standardDeviation(
        uint256[] memory values
    ) internal pure returns (uint256 result) {
        if (values.length == 0) revert Math__InvalidInput();
        if (values.length == 1) return 0;

        // Calculate mean
        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }
        uint256 mean = sum / values.length;

        // Calculate variance
        uint256 variance = 0;
        for (uint256 i = 0; i < values.length; i++) {
            uint256 diff = absDiff(values[i], mean);
            variance += mulWad(diff, diff);
        }
        variance = variance / values.length;

        // Return standard deviation
        result = sqrt(variance);
    }

    /**
     * @notice Calculate Sharpe ratio for risk-adjusted returns
     * @param returnValues Array of returns
     * @param riskFreeRate Risk-free rate
     * @return result Sharpe ratio
     */
    function sharpeRatio(
        uint256[] memory returnValues,
        uint256 riskFreeRate
    ) internal pure returns (uint256 result) {
        if (returnValues.length == 0) revert Math__InvalidInput();

        // Calculate mean return
        uint256 sum = 0;
        for (uint256 i = 0; i < returnValues.length; i++) {
            sum += returnValues[i];
        }
        uint256 meanReturn = sum / returnValues.length;

        // Calculate excess return
        if (meanReturn <= riskFreeRate) return 0;
        uint256 excessReturn = meanReturn - riskFreeRate;

        // Calculate standard deviation of returns
        uint256 stdDev = standardDeviation(returnValues);
        if (stdDev == 0) revert Math__DivisionByZero();

        result = divWad(excessReturn, stdDev);
    }

    /**
     * @notice Calculate correlation coefficient between two arrays
     * @param x First array
     * @param y Second array
     * @return result Correlation coefficient (-PRECISION to PRECISION)
     */
    function correlation(
        uint256[] memory x,
        uint256[] memory y
    ) internal pure returns (int256 result) {
        if (x.length != y.length || x.length == 0) revert Math__InvalidInput();

        // Calculate means
        uint256 meanX = 0;
        uint256 meanY = 0;
        for (uint256 i = 0; i < x.length; i++) {
            meanX += x[i];
            meanY += y[i];
        }
        meanX = meanX / x.length;
        meanY = meanY / y.length;

        // Calculate numerator and denominators
        int256 numerator = 0;
        uint256 sumXSq = 0;
        uint256 sumYSq = 0;

        for (uint256 i = 0; i < x.length; i++) {
            int256 diffX = int256(x[i]) - int256(meanX);
            int256 diffY = int256(y[i]) - int256(meanY);

            numerator += diffX * diffY;
            sumXSq += uint256(diffX * diffX);
            sumYSq += uint256(diffY * diffY);
        }

        uint256 denominator = sqrt(mulWad(sumXSq, sumYSq));
        if (denominator == 0) return 0;

        result = (numerator * int256(PRECISION)) / int256(denominator);
    }

    /**
     * @notice Calculate Value at Risk (VaR) using historical method
     * @param returnValues Array of historical returns
     * @param confidenceLevel Confidence level (e.g., 95 for 95%)
     * @return result VaR value
     */
    function calculateVaR(
        int256[] memory returnValues,
        uint256 confidenceLevel
    ) internal pure returns (uint256 result) {
        if (returnValues.length == 0 || confidenceLevel >= 100)
            revert Math__InvalidInput();

        // Sort returns (simple bubble sort for small arrays)
        for (uint256 i = 0; i < returnValues.length - 1; i++) {
            for (uint256 j = 0; j < returnValues.length - i - 1; j++) {
                if (returnValues[j] > returnValues[j + 1]) {
                    int256 temp = returnValues[j];
                    returnValues[j] = returnValues[j + 1];
                    returnValues[j + 1] = temp;
                }
            }
        }

        // Find percentile
        uint256 index = ((100 - confidenceLevel) * returnValues.length) / 100;
        if (index >= returnValues.length) index = returnValues.length - 1;

        // Return absolute value of the loss
        result = returnValues[index] < 0 ? uint256(-returnValues[index]) : 0;
    }

    /**
     * @notice Calculate Black-Scholes option price (simplified)
     * @param spot Current spot price
     * @param strike Strike price
     * @param timeToExpiry Time to expiry (in years, scaled)
     * @param volatility Volatility (scaled)
     * @param isCall True for call option, false for put
     * @return result Option price
     */
    function blackScholes(
        uint256 spot,
        uint256 strike,
        uint256 timeToExpiry,
        uint256 volatility,
        uint256 /* riskFreeRate - unused in simplified implementation */,
        bool isCall
    ) internal pure returns (uint256 result) {
        if (spot == 0 || strike == 0 || timeToExpiry == 0 || volatility == 0) {
            return 0;
        }

        // This is a simplified implementation
        // In practice, you'd need a more sophisticated normal distribution function

        // Calculate d1 and d2
        uint256 sqrtT = sqrt(timeToExpiry);
        uint256 volSqrtT = mulWad(volatility, sqrtT);

        // Simplified calculation for demonstration
        if (isCall) {
            result = spot > strike ? spot - strike : 0;
        } else {
            result = strike > spot ? strike - spot : 0;
        }

        // Apply time value decay (simplified)
        uint256 timeValue = mulWad(volSqrtT, spot / 10);
        result += timeValue;
    }

    /**
     * @notice Convert basis points to decimal
     * @param bps Basis points
     * @return result Decimal value (scaled by PRECISION)
     */
    function bpsToDecimal(uint256 bps) internal pure returns (uint256 result) {
        result = (bps * PRECISION) / 10000;
    }

    /**
     * @notice Convert decimal to basis points
     * @param decimal Decimal value (scaled by PRECISION)
     * @return result Basis points
     */
    function decimalToBps(
        uint256 decimal
    ) internal pure returns (uint256 result) {
        result = (decimal * 10000) / PRECISION;
    }

    /**
     * @notice Calculate annualized rate from period rate
     * @param periodRate Rate for specific period
     * @param periodsPerYear Number of periods per year
     * @return result Annualized rate
     */
    function annualizeRate(
        uint256 periodRate,
        uint256 periodsPerYear
    ) internal pure returns (uint256 result) {
        if (periodsPerYear == 0) revert Math__DivisionByZero();

        // Use compound interest formula: (1 + r)^n - 1
        uint256 onePlusRate = PRECISION + periodRate;
        result = pow(onePlusRate, periodsPerYear) - PRECISION;
    }

    /**
     * @notice Calculate period rate from annualized rate
     * @param annualRate Annualized rate
     * @param periodsPerYear Number of periods per year
     * @return result Period rate
     */
    function deannualizeRate(
        uint256 annualRate,
        uint256 periodsPerYear
    ) internal pure returns (uint256 result) {
        if (periodsPerYear == 0) revert Math__DivisionByZero();

        // Use: (1 + r_annual)^(1/n) - 1
        uint256 onePlusAnnual = PRECISION + annualRate;
        uint256 fractionalExponent = divWad(PRECISION, periodsPerYear);
        result = pow(onePlusAnnual, fractionalExponent) - PRECISION;
    }
}
