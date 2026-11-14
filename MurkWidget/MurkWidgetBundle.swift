import WidgetKit
import SwiftUI

// Kept in its own file so the widget views can be compiled into the render tests without `@main`.
@main
struct MurkWidgetBundle: WidgetBundle {
    var body: some Widget {
        MurkWeatherWidget()
        MurkRainWidget()
        MurkAirWidget()
        MurkDaylightWidget()
        MurkMoonWidget()
        RainActivityWidget()
    }
}
