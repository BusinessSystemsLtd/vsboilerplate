namespace SolutionName.Core.Tests
{
    using FluentAssertions;

    using Xunit;
    using Xunit.Extensions;

    public class CalculatorFacts
    {
        [Fact]
        public void Calculator_should_add_1_and_2()
        {
            var sut = new Calculator();
            var result = sut.Add(1, 2);

            result.Should().Be(3);
        }

        [Theory]
        [InlineData(2, 3)]
        [InlineData(10, 100)]
        public void Calculator_should_add(int a, int b)
        {
            var sut = new Calculator();
            var result = sut.Add(a, b);

            result.Should().Be(a + b);
        }
    }
}
