using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace WpfApp.ViewModels;

/// <summary>View model backing <see cref="MainWindow"/>.</summary>
public class MainViewModel : INotifyPropertyChanged
{
    private string _name = "world";

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>Name the greeting is addressed to.</summary>
    public string Name
    {
        get => _name;
        set
        {
            if (_name == value)
            {
                return;
            }

            _name = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(Greeting));
        }
    }

    /// <summary>Greeting derived from <see cref="Name"/>.</summary>
    public string Greeting => $"Hello, {Name}!";

    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
