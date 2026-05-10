package com.example;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.notification.Notification;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.Route;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}

@Route("")
class MainView extends VerticalLayout {

    private int count = 0;

    public MainView() {
        H1 heading = new H1("Hello from Vaadin in CodingBooth!");
        Paragraph description = new Paragraph("Click the button — UI updates without writing any JavaScript.");
        Button button = new Button("Click me", event -> {
            count++;
            Notification.show("Clicked " + count + " time" + (count == 1 ? "" : "s"));
        });
        add(heading, description, button);
    }
}
