"""Entry point for the `app` console script."""


def greeting(name: str) -> str:
    """Return a greeting addressed to ``name``."""
    return f"Hello, {name}!"


def main() -> None:
    """Print the default greeting."""
    print(greeting("world"))


if __name__ == "__main__":
    main()
