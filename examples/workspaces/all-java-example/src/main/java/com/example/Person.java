package com.example;

import lombok.Value;

@Value
public class Person {
    private final String name;
    private final int    age;
    
    public Person(String name, int age) {
        this.name = name;
        this.age  = age;
    }
    
    public static void main(String[] args) {
        var person = new Person("Peter Parker", 18);
        System.out.println("Hello, %s (%d)!".formatted(person.name, person.age));
    }
}

