using App.ViewModels;
using Xunit;

namespace App.Tests;

public class MainViewModelTests
{
    [Fact]
    public void GreetsByName()
    {
        var vm = new MainViewModel { Name = "world" };

        Assert.Equal("Hello, world!", vm.Greeting);
    }

    [Fact]
    public void RaisesPropertyChangedForGreetingWhenNameChanges()
    {
        var vm = new MainViewModel();
        var changed = new List<string?>();
        vm.PropertyChanged += (_, e) => changed.Add(e.PropertyName);

        vm.Name = "Ada";

        Assert.Contains(nameof(MainViewModel.Name), changed);
        Assert.Contains(nameof(MainViewModel.Greeting), changed);
    }
}
