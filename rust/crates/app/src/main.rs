fn greeting(name: &str) -> String {
    format!("Hello, {name}!")
}

fn main() {
    println!("{}", greeting("world"));
}

#[cfg(test)]
mod tests {
    use super::greeting;

    #[test]
    fn greets_by_name() {
        assert_eq!(greeting("world"), "Hello, world!");
    }
}
