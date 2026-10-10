//! Pure raster/GIF generation for the built-in sticker catalog.
use image::{
    codecs::gif::{GifEncoder, Repeat},
    Delay, DynamicImage, Frame, ImageFormat, Rgba, RgbaImage,
};
use std::io::Cursor;

fn fill_circle(image: &mut RgbaImage, cx: i32, cy: i32, radius: i32, color: Rgba<u8>) {
    let radius_sq = radius * radius;
    for y in (cy - radius).max(0)..=(cy + radius).min(image.height() as i32 - 1) {
        for x in (cx - radius).max(0)..=(cx + radius).min(image.width() as i32 - 1) {
            let dx = x - cx;
            let dy = y - cy;
            if dx * dx + dy * dy <= radius_sq {
                image.put_pixel(x as u32, y as u32, color);
            }
        }
    }
}

fn fill_rect(image: &mut RgbaImage, x: i32, y: i32, width: i32, height: i32, color: Rgba<u8>) {
    for py in y.max(0)..(y + height).min(image.height() as i32) {
        for px in x.max(0)..(x + width).min(image.width() as i32) {
            image.put_pixel(px as u32, py as u32, color);
        }
    }
}

fn fill_polygon(image: &mut RgbaImage, points: &[(i32, i32)], color: Rgba<u8>) {
    if points.len() < 3 {
        return;
    }
    let min_x = points.iter().map(|point| point.0).min().unwrap_or(0).max(0);
    let max_x = points
        .iter()
        .map(|point| point.0)
        .max()
        .unwrap_or(0)
        .min(image.width() as i32 - 1);
    let min_y = points.iter().map(|point| point.1).min().unwrap_or(0).max(0);
    let max_y = points
        .iter()
        .map(|point| point.1)
        .max()
        .unwrap_or(0)
        .min(image.height() as i32 - 1);

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let mut inside = false;
            let mut previous = points.len() - 1;
            for current in 0..points.len() {
                let (xi, yi) = points[current];
                let (xj, yj) = points[previous];
                let crosses = (yi > y) != (yj > y)
                    && (x as f64)
                        < (xj - xi) as f64 * (y - yi) as f64 / (yj - yi) as f64 + xi as f64;
                if crosses {
                    inside = !inside;
                }
                previous = current;
            }
            if inside {
                image.put_pixel(x as u32, y as u32, color);
            }
        }
    }
}

fn draw_thick_line(
    image: &mut RgbaImage,
    from: (i32, i32),
    to: (i32, i32),
    thickness: i32,
    color: Rgba<u8>,
) {
    let dx = to.0 - from.0;
    let dy = to.1 - from.1;
    let steps = dx.abs().max(dy.abs()).max(1);
    let radius = (thickness / 2).max(1);
    for step in 0..=steps {
        let t = step as f64 / steps as f64;
        let x = (from.0 as f64 + dx as f64 * t).round() as i32;
        let y = (from.1 as f64 + dy as f64 * t).round() as i32;
        fill_circle(image, x, y, radius, color);
    }
}

fn star_points(cx: i32, cy: i32, outer: f64, inner: f64) -> Vec<(i32, i32)> {
    let mut result = Vec::with_capacity(10);
    for index in 0..10 {
        let radius = if index % 2 == 0 { outer } else { inner };
        let angle = -std::f64::consts::FRAC_PI_2 + index as f64 * std::f64::consts::PI / 5.0;
        result.push((
            (cx as f64 + radius * angle.cos()).round() as i32,
            (cy as f64 + radius * angle.sin()).round() as i32,
        ));
    }
    result
}

fn render_builtin_sticker(sticker_id: &str) -> Result<(Vec<u8>, &'static str), String> {
    let mut image = RgbaImage::from_pixel(256, 256, Rgba([0, 0, 0, 0]));
    let outline = Rgba([28, 31, 36, 235]);

    let body = match sticker_id {
        "heart" => {
            let color = Rgba([255, 90, 125, 255]);
            fill_circle(&mut image, 86, 92, 60, outline);
            fill_circle(&mut image, 170, 92, 60, outline);
            fill_polygon(&mut image, &[(28, 102), (228, 102), (128, 226)], outline);
            fill_circle(&mut image, 88, 94, 50, color);
            fill_circle(&mut image, 168, 94, 50, color);
            fill_polygon(&mut image, &[(42, 104), (214, 104), (128, 210)], color);
            "Сердце"
        }
        "star" => {
            let color = Rgba([255, 201, 74, 255]);
            fill_polygon(&mut image, &star_points(128, 128, 104.0, 52.0), outline);
            fill_polygon(&mut image, &star_points(128, 128, 91.0, 45.0), color);
            "Звезда"
        }
        "check" => {
            let color = Rgba([66, 217, 130, 255]);
            draw_thick_line(&mut image, (51, 132), (106, 188), 38, outline);
            draw_thick_line(&mut image, (106, 188), (210, 70), 38, outline);
            draw_thick_line(&mut image, (51, 132), (106, 188), 24, color);
            draw_thick_line(&mut image, (106, 188), (210, 70), 24, color);
            "Готово"
        }
        "alert" => {
            let color = Rgba([255, 138, 76, 255]);
            fill_polygon(&mut image, &[(128, 25), (235, 220), (21, 220)], outline);
            fill_polygon(&mut image, &[(128, 43), (219, 209), (37, 209)], color);
            fill_rect(&mut image, 117, 90, 22, 68, outline);
            fill_circle(&mut image, 128, 181, 13, outline);
            "Внимание"
        }
        "smile" => {
            let color = Rgba([255, 216, 77, 255]);
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, color);
            fill_circle(&mut image, 94, 105, 12, outline);
            fill_circle(&mut image, 162, 105, 12, outline);
            let mut previous = None;
            for step in 0..=36 {
                let angle = 0.18 * std::f64::consts::PI
                    + (0.64 * std::f64::consts::PI) * step as f64 / 36.0;
                let point = (
                    (128.0 + 58.0 * angle.cos()).round() as i32,
                    (124.0 + 58.0 * angle.sin()).round() as i32,
                );
                if let Some(last) = previous {
                    draw_thick_line(&mut image, last, point, 11, outline);
                }
                previous = Some(point);
            }
            "Улыбка"
        }
        "party" => {
            let purple = Rgba([183, 136, 255, 255]);
            let cyan = Rgba([83, 220, 232, 255]);
            let yellow = Rgba([255, 208, 82, 255]);
            fill_polygon(&mut image, &[(57, 205), (104, 61), (205, 214)], outline);
            fill_polygon(&mut image, &[(72, 197), (108, 79), (190, 202)], purple);
            draw_thick_line(&mut image, (81, 159), (165, 183), 10, cyan);
            draw_thick_line(&mut image, (91, 128), (151, 146), 9, yellow);
            fill_circle(&mut image, 185, 62, 13, cyan);
            fill_circle(&mut image, 211, 104, 10, yellow);
            fill_circle(&mut image, 149, 38, 9, purple);
            draw_thick_line(&mut image, (184, 27), (195, 47), 8, yellow);
            draw_thick_line(&mut image, (218, 52), (232, 39), 8, cyan);
            "Праздник"
        }
        _ => return Err("Неизвестный встроенный стикер".to_owned()),
    };

    let mut encoded = Cursor::new(Vec::new());
    DynamicImage::ImageRgba8(image)
        .write_to(&mut encoded, ImageFormat::Png)
        .map_err(|error| format!("Не удалось создать встроенный стикер: {error}"))?;
    Ok((encoded.into_inner(), body))
}

fn render_extended_shape(
    sticker_id: &str,
    phase: f64,
) -> Result<(RgbaImage, &'static str), String> {
    let mut image = RgbaImage::from_pixel(256, 256, Rgba([0, 0, 0, 0]));
    let outline = Rgba([28, 31, 36, 235]);
    let skin = Rgba([255, 208, 132, 255]);
    let yellow = Rgba([255, 216, 77, 255]);
    let blue = Rgba([89, 186, 255, 255]);
    let red = Rgba([255, 91, 91, 255]);
    let green = Rgba([66, 217, 130, 255]);

    let body = match sticker_id {
        "thumbs_up" => {
            fill_circle(&mut image, 128, 132, 93, outline);
            fill_circle(&mut image, 128, 132, 82, Rgba([68, 86, 102, 255]));
            fill_rect(&mut image, 84, 112, 45, 78, outline);
            fill_rect(&mut image, 94, 118, 31, 62, skin);
            fill_polygon(
                &mut image,
                &[(119, 121), (149, 69), (169, 77), (154, 122)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(125, 117), (150, 80), (158, 84), (146, 123)],
                skin,
            );
            fill_rect(&mut image, 128, 118, 55, 23, outline);
            fill_rect(&mut image, 132, 123, 44, 13, skin);
            "Класс"
        }
        "fire" => {
            fill_polygon(
                &mut image,
                &[
                    (128, 25),
                    (193, 109),
                    (181, 202),
                    (128, 231),
                    (69, 202),
                    (57, 124),
                    (100, 77),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (128, 43),
                    (178, 116),
                    (166, 194),
                    (128, 216),
                    (82, 190),
                    (72, 132),
                    (111, 86),
                ],
                Rgba([255, 111, 54, 255]),
            );
            fill_polygon(
                &mut image,
                &[
                    (128, 102),
                    (155, 145),
                    (150, 184),
                    (128, 199),
                    (103, 180),
                    (102, 147),
                ],
                Rgba([255, 214, 71, 255]),
            );
            "Огонь"
        }
        "rocket" => {
            fill_polygon(
                &mut image,
                &[
                    (128, 29),
                    (181, 91),
                    (164, 174),
                    (128, 203),
                    (92, 174),
                    (75, 91),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (128, 45),
                    (168, 96),
                    (154, 165),
                    (128, 187),
                    (102, 165),
                    (88, 96),
                ],
                Rgba([224, 235, 244, 255]),
            );
            fill_circle(&mut image, 128, 105, 24, outline);
            fill_circle(&mut image, 128, 105, 15, blue);
            fill_polygon(&mut image, &[(102, 165), (68, 196), (93, 125)], red);
            fill_polygon(&mut image, &[(154, 165), (188, 196), (163, 125)], red);
            fill_polygon(
                &mut image,
                &[(111, 190), (128, 232), (145, 190)],
                Rgba([255, 159, 45, 255]),
            );
            "Поехали"
        }
        "laugh" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, yellow);
            draw_thick_line(&mut image, (72, 102), (102, 113), 12, outline);
            draw_thick_line(&mut image, (154, 113), (184, 102), 12, outline);
            fill_polygon(
                &mut image,
                &[(77, 145), (179, 145), (160, 197), (96, 197)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(92, 157), (164, 157), (150, 184), (106, 184)],
                Rgba([180, 45, 61, 255]),
            );
            fill_polygon(
                &mut image,
                &[(64, 116), (48, 145), (65, 156), (79, 136)],
                blue,
            );
            fill_polygon(
                &mut image,
                &[(192, 116), (208, 145), (191, 156), (177, 136)],
                blue,
            );
            "Смешно"
        }
        "sad" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, Rgba([113, 185, 255, 255]));
            fill_circle(&mut image, 93, 109, 11, outline);
            fill_circle(&mut image, 163, 109, 11, outline);
            let mut previous = None;
            for step in 0..=30 {
                let angle =
                    1.16 * std::f64::consts::PI + 0.68 * std::f64::consts::PI * step as f64 / 30.0;
                let point = (
                    (128.0 + 52.0 * angle.cos()).round() as i32,
                    (194.0 + 45.0 * angle.sin()).round() as i32,
                );
                if let Some(last) = previous {
                    draw_thick_line(&mut image, last, point, 9, outline);
                }
                previous = Some(point);
            }
            "Грустно"
        }
        "wow" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, yellow);
            fill_circle(&mut image, 92, 104, 13, outline);
            fill_circle(&mut image, 164, 104, 13, outline);
            fill_circle(&mut image, 128, 166, 30, outline);
            fill_circle(&mut image, 128, 166, 18, Rgba([103, 62, 55, 255]));
            "Вау"
        }
        "wave" => {
            fill_circle(&mut image, 125, 136, 75, outline);
            fill_circle(&mut image, 125, 136, 64, skin);
            for offset in [(-47, -73), (-17, -88), (14, -87), (44, -72)] {
                draw_thick_line(
                    &mut image,
                    (125 + offset.0 / 2, 122 + offset.1 / 3),
                    (125 + offset.0, 122 + offset.1),
                    30,
                    outline,
                );
                draw_thick_line(
                    &mut image,
                    (125 + offset.0 / 2, 122 + offset.1 / 3),
                    (125 + offset.0, 122 + offset.1),
                    19,
                    skin,
                );
            }
            draw_thick_line(&mut image, (178, 167), (219, 138), 31, outline);
            draw_thick_line(&mut image, (178, 167), (216, 142), 19, skin);
            "Привет"
        }
        "clap" => {
            fill_polygon(
                &mut image,
                &[(54, 177), (93, 58), (143, 76), (111, 200)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(68, 174), (100, 73), (130, 84), (101, 186)],
                skin,
            );
            fill_polygon(
                &mut image,
                &[(116, 190), (155, 65), (207, 91), (161, 210)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(130, 185), (162, 80), (193, 97), (153, 196)],
                skin,
            );
            draw_thick_line(&mut image, (52, 79), (27, 55), 8, yellow);
            draw_thick_line(&mut image, (199, 58), (222, 34), 8, yellow);
            "Аплодисменты"
        }
        "coffee" => {
            fill_rect(&mut image, 57, 88, 122, 104, outline);
            fill_rect(&mut image, 69, 100, 98, 80, Rgba([242, 236, 220, 255]));
            fill_circle(&mut image, 182, 137, 42, outline);
            fill_circle(&mut image, 182, 137, 28, Rgba([0, 0, 0, 0]));
            fill_rect(&mut image, 75, 102, 86, 18, Rgba([111, 72, 48, 255]));
            draw_thick_line(
                &mut image,
                (93, 73),
                (105, 38),
                8,
                Rgba([199, 214, 220, 220]),
            );
            draw_thick_line(
                &mut image,
                (132, 73),
                (142, 34),
                8,
                Rgba([199, 214, 220, 220]),
            );
            "Кофе"
        }
        "idea" => {
            fill_circle(&mut image, 128, 105, 76, outline);
            fill_circle(&mut image, 128, 105, 64, yellow);
            fill_polygon(
                &mut image,
                &[(92, 142), (164, 142), (148, 182), (108, 182)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(105, 147), (151, 147), (140, 170), (116, 170)],
                Rgba([246, 191, 56, 255]),
            );
            fill_rect(&mut image, 105, 181, 46, 20, outline);
            fill_rect(&mut image, 114, 185, 28, 11, Rgba([160, 171, 178, 255]));
            for (a, b) in [
                ((128, 13), (128, 0)),
                ((53, 43), (39, 29)),
                ((203, 43), (217, 29)),
            ] {
                draw_thick_line(&mut image, a, b, 8, yellow);
            }
            "Идея"
        }
        "thumbs_down" => {
            fill_circle(&mut image, 128, 124, 94, outline);
            fill_circle(&mut image, 128, 124, 82, Rgba([68, 86, 102, 255]));
            fill_rect(&mut image, 84, 67, 45, 78, outline);
            fill_rect(&mut image, 94, 77, 31, 62, skin);
            fill_polygon(
                &mut image,
                &[(119, 137), (149, 189), (169, 181), (154, 136)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(125, 141), (150, 178), (158, 174), (146, 135)],
                skin,
            );
            fill_rect(&mut image, 128, 115, 55, 23, outline);
            fill_rect(&mut image, 132, 120, 44, 13, skin);
            "Не нравится"
        }
        "love" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, yellow);
            let heart_color = Rgba([255, 82, 118, 255]);
            for cx in [91, 165] {
                fill_circle(&mut image, cx - 8, 104, 13, heart_color);
                fill_circle(&mut image, cx + 8, 104, 13, heart_color);
                fill_polygon(
                    &mut image,
                    &[(cx - 20, 108), (cx + 20, 108), (cx, 134)],
                    heart_color,
                );
            }
            draw_thick_line(&mut image, (91, 159), (128, 181), 9, outline);
            draw_thick_line(&mut image, (128, 181), (169, 151), 9, outline);
            "Влюблён"
        }
        "cool" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, yellow);
            fill_rect(&mut image, 61, 91, 57, 34, outline);
            fill_rect(&mut image, 138, 91, 57, 34, outline);
            fill_rect(&mut image, 113, 99, 30, 9, outline);
            fill_rect(&mut image, 69, 98, 41, 20, Rgba([43, 57, 73, 255]));
            fill_rect(&mut image, 146, 98, 41, 20, Rgba([43, 57, 73, 255]));
            draw_thick_line(&mut image, (88, 158), (128, 176), 9, outline);
            draw_thick_line(&mut image, (128, 176), (170, 151), 9, outline);
            "Круто"
        }
        "angry" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, Rgba([255, 101, 101, 255]));
            draw_thick_line(&mut image, (69, 87), (108, 102), 10, outline);
            draw_thick_line(&mut image, (148, 102), (187, 87), 10, outline);
            fill_circle(&mut image, 94, 111, 10, outline);
            fill_circle(&mut image, 162, 111, 10, outline);
            draw_thick_line(&mut image, (91, 181), (128, 160), 9, outline);
            draw_thick_line(&mut image, (128, 160), (169, 184), 9, outline);
            "Злюсь"
        }
        "cry" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, yellow);
            fill_circle(&mut image, 92, 108, 11, outline);
            fill_circle(&mut image, 164, 108, 11, outline);
            fill_polygon(&mut image, &[(72, 119), (88, 157), (56, 157)], blue);
            fill_circle(&mut image, 72, 158, 16, blue);
            draw_thick_line(&mut image, (91, 181), (128, 160), 9, outline);
            draw_thick_line(&mut image, (128, 160), (169, 184), 9, outline);
            "Плачу"
        }
        "sleepy" => {
            fill_circle(&mut image, 122, 136, 93, outline);
            fill_circle(&mut image, 122, 136, 82, Rgba([183, 156, 255, 255]));
            draw_thick_line(&mut image, (70, 116), (101, 116), 8, outline);
            draw_thick_line(&mut image, (139, 116), (170, 116), 8, outline);
            fill_circle(&mut image, 121, 169, 15, outline);
            draw_thick_line(&mut image, (177, 72), (211, 72), 8, blue);
            draw_thick_line(&mut image, (211, 72), (177, 103), 8, blue);
            draw_thick_line(&mut image, (177, 103), (211, 103), 8, blue);
            draw_thick_line(&mut image, (199, 37), (227, 37), 7, blue);
            draw_thick_line(&mut image, (227, 37), (199, 60), 7, blue);
            draw_thick_line(&mut image, (199, 60), (227, 60), 7, blue);
            "Спать"
        }
        "thinking" => {
            fill_circle(&mut image, 123, 119, 91, outline);
            fill_circle(&mut image, 123, 119, 80, yellow);
            fill_circle(&mut image, 91, 108, 10, outline);
            fill_circle(&mut image, 155, 108, 10, outline);
            draw_thick_line(&mut image, (76, 82), (104, 75), 8, outline);
            draw_thick_line(&mut image, (140, 76), (170, 83), 8, outline);
            draw_thick_line(&mut image, (104, 158), (151, 155), 8, outline);
            fill_circle(&mut image, 174, 184, 34, outline);
            fill_circle(&mut image, 174, 184, 25, skin);
            fill_circle(&mut image, 145, 204, 18, outline);
            fill_circle(&mut image, 145, 204, 11, skin);
            "Думаю"
        }
        "question" => {
            fill_circle(&mut image, 128, 128, 105, outline);
            fill_circle(&mut image, 128, 128, 91, Rgba([98, 171, 255, 255]));
            draw_thick_line(&mut image, (96, 88), (111, 68), 19, outline);
            draw_thick_line(&mut image, (111, 68), (151, 68), 19, outline);
            draw_thick_line(&mut image, (151, 68), (166, 86), 19, outline);
            draw_thick_line(&mut image, (166, 86), (158, 108), 19, outline);
            draw_thick_line(&mut image, (158, 108), (127, 130), 19, outline);
            draw_thick_line(&mut image, (127, 130), (127, 148), 19, outline);
            fill_circle(&mut image, 127, 184, 12, outline);
            "Вопрос"
        }
        "lightning" => {
            let bolt = [
                (142, 20),
                (72, 135),
                (116, 135),
                (94, 233),
                (187, 111),
                (142, 111),
            ];
            let bolt_inner = [
                (139, 39),
                (88, 127),
                (128, 127),
                (111, 209),
                (171, 119),
                (133, 119),
            ];
            fill_polygon(&mut image, &bolt, outline);
            fill_polygon(&mut image, &bolt_inner, Rgba([255, 225, 78, 255]));
            "Молния"
        }
        "sparkle" => {
            let gold = Rgba([255, 217, 93, 255]);
            fill_polygon(
                &mut image,
                &[
                    (128, 22),
                    (151, 104),
                    (233, 128),
                    (151, 151),
                    (128, 234),
                    (105, 151),
                    (23, 128),
                    (105, 104),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (128, 42),
                    (145, 111),
                    (214, 128),
                    (145, 145),
                    (128, 214),
                    (111, 145),
                    (42, 128),
                    (111, 111),
                ],
                gold,
            );
            fill_polygon(
                &mut image,
                &[
                    (57, 34),
                    (64, 57),
                    (87, 64),
                    (64, 71),
                    (57, 94),
                    (50, 71),
                    (27, 64),
                    (50, 57),
                ],
                Rgba([255, 244, 174, 255]),
            );
            "Блеск"
        }
        "gift" => {
            let red_box = Rgba([255, 92, 121, 255]);
            fill_rect(&mut image, 48, 95, 160, 125, outline);
            fill_rect(&mut image, 59, 106, 138, 103, red_box);
            fill_rect(&mut image, 38, 76, 180, 48, outline);
            fill_rect(&mut image, 49, 86, 158, 27, Rgba([255, 118, 143, 255]));
            fill_rect(&mut image, 115, 82, 26, 127, Rgba([255, 214, 79, 255]));
            fill_circle(&mut image, 99, 66, 31, outline);
            fill_circle(&mut image, 157, 66, 31, outline);
            fill_circle(&mut image, 100, 67, 20, Rgba([255, 214, 79, 255]));
            fill_circle(&mut image, 156, 67, 20, Rgba([255, 214, 79, 255]));
            "Подарок"
        }
        "music" => {
            let purple = Rgba([184, 137, 255, 255]);
            draw_thick_line(&mut image, (102, 60), (102, 176), 16, outline);
            draw_thick_line(&mut image, (165, 45), (165, 160), 16, outline);
            draw_thick_line(&mut image, (102, 60), (165, 45), 18, outline);
            draw_thick_line(&mut image, (102, 69), (165, 54), 10, purple);
            fill_circle(&mut image, 80, 184, 35, outline);
            fill_circle(&mut image, 80, 184, 25, purple);
            fill_circle(&mut image, 143, 168, 35, outline);
            fill_circle(&mut image, 143, 168, 25, purple);
            "Музыка"
        }
        "stop" => {
            let red_sign = Rgba([255, 100, 100, 255]);
            let points = [
                (85, 30),
                (171, 30),
                (226, 85),
                (226, 171),
                (171, 226),
                (85, 226),
                (30, 171),
                (30, 85),
            ];
            fill_polygon(&mut image, &points, outline);
            let inner = [
                (90, 43),
                (166, 43),
                (213, 90),
                (213, 166),
                (166, 213),
                (90, 213),
                (43, 166),
                (43, 90),
            ];
            fill_polygon(&mut image, &inner, red_sign);
            fill_rect(&mut image, 68, 113, 120, 30, Rgba([255, 255, 255, 255]));
            "Стоп"
        }
        "yes" => {
            fill_circle(&mut image, 128, 128, 101, outline);
            fill_circle(&mut image, 128, 128, 88, green);
            draw_thick_line(
                &mut image,
                (72, 132),
                (111, 171),
                22,
                Rgba([255, 255, 255, 255]),
            );
            draw_thick_line(
                &mut image,
                (111, 171),
                (188, 86),
                22,
                Rgba([255, 255, 255, 255]),
            );
            "Да"
        }
        "no" => {
            fill_circle(&mut image, 128, 128, 101, outline);
            fill_circle(&mut image, 128, 128, 88, red);
            draw_thick_line(
                &mut image,
                (83, 83),
                (173, 173),
                22,
                Rgba([255, 255, 255, 255]),
            );
            draw_thick_line(
                &mut image,
                (173, 83),
                (83, 173),
                22,
                Rgba([255, 255, 255, 255]),
            );
            "Нет"
        }
        "sun" => {
            fill_circle(&mut image, 128, 128, 60, outline);
            fill_circle(&mut image, 128, 128, 49, yellow);
            for index in 0..12 {
                let angle = index as f64 * std::f64::consts::TAU / 12.0;
                let a = (
                    (128.0 + angle.cos() * 77.0) as i32,
                    (128.0 + angle.sin() * 77.0) as i32,
                );
                let b = (
                    (128.0 + angle.cos() * 105.0) as i32,
                    (128.0 + angle.sin() * 105.0) as i32,
                );
                draw_thick_line(&mut image, a, b, 10, yellow);
            }
            "Солнце"
        }
        "moon" => {
            fill_circle(&mut image, 120, 126, 92, outline);
            fill_circle(&mut image, 120, 126, 80, Rgba([168, 184, 255, 255]));
            fill_circle(&mut image, 158, 98, 70, Rgba([0, 0, 0, 0]));
            "Луна"
        }
        "crown" => {
            let gold = Rgba([255, 211, 92, 255]);
            fill_polygon(
                &mut image,
                &[
                    (48, 81),
                    (89, 127),
                    (128, 58),
                    (167, 127),
                    (208, 81),
                    (187, 194),
                    (69, 194),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (62, 98),
                    (92, 139),
                    (128, 79),
                    (164, 139),
                    (194, 98),
                    (176, 181),
                    (80, 181),
                ],
                gold,
            );
            fill_circle(&mut image, 128, 148, 10, Rgba([255, 96, 122, 255]));
            fill_circle(&mut image, 92, 155, 8, blue);
            fill_circle(&mut image, 164, 155, 8, green);
            "Корона"
        }
        "trophy" => {
            let gold = Rgba([255, 201, 74, 255]);
            fill_polygon(
                &mut image,
                &[
                    (72, 47),
                    (184, 47),
                    (170, 139),
                    (145, 163),
                    (111, 163),
                    (86, 139),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (85, 59),
                    (171, 59),
                    (159, 131),
                    (140, 149),
                    (116, 149),
                    (97, 131),
                ],
                gold,
            );
            draw_thick_line(&mut image, (73, 70), (38, 72), 13, outline);
            draw_thick_line(&mut image, (38, 72), (47, 121), 13, outline);
            draw_thick_line(&mut image, (183, 70), (218, 72), 13, outline);
            draw_thick_line(&mut image, (218, 72), (209, 121), 13, outline);
            fill_rect(&mut image, 118, 159, 20, 41, outline);
            fill_rect(&mut image, 84, 193, 88, 25, outline);
            fill_rect(&mut image, 94, 201, 68, 10, gold);
            "Победа"
        }
        "pizza" => {
            let crust = Rgba([211, 137, 72, 255]);
            let cheese = Rgba([255, 205, 78, 255]);
            fill_polygon(&mut image, &[(128, 31), (222, 206), (34, 206)], outline);
            fill_polygon(&mut image, &[(128, 49), (204, 192), (52, 192)], cheese);
            draw_thick_line(&mut image, (48, 198), (208, 198), 25, outline);
            draw_thick_line(&mut image, (55, 198), (201, 198), 13, crust);
            for (x, y) in [(107, 103), (158, 132), (93, 159)] {
                fill_circle(&mut image, x, y, 16, outline);
                fill_circle(&mut image, x, y, 11, Rgba([224, 74, 69, 255]));
            }
            "Пицца"
        }
        "cloud" => {
            let cloud = Rgba([182, 197, 212, 255]);
            fill_circle(&mut image, 95, 132, 55, outline);
            fill_circle(&mut image, 145, 111, 67, outline);
            fill_circle(&mut image, 184, 143, 48, outline);
            fill_rect(&mut image, 61, 132, 155, 63, outline);
            fill_circle(&mut image, 95, 132, 43, cloud);
            fill_circle(&mut image, 145, 111, 55, cloud);
            fill_circle(&mut image, 184, 143, 36, cloud);
            fill_rect(&mut image, 70, 136, 137, 48, cloud);
            "Облачно"
        }
        "rain" => {
            let cloud = Rgba([168, 188, 207, 255]);
            fill_circle(&mut image, 94, 100, 45, outline);
            fill_circle(&mut image, 139, 83, 55, outline);
            fill_circle(&mut image, 180, 110, 39, outline);
            fill_rect(&mut image, 64, 102, 143, 45, outline);
            fill_circle(&mut image, 94, 100, 34, cloud);
            fill_circle(&mut image, 139, 83, 44, cloud);
            fill_circle(&mut image, 180, 110, 28, cloud);
            fill_rect(&mut image, 73, 108, 125, 28, cloud);
            for x in [88, 128, 168] {
                draw_thick_line(&mut image, (x, 159), (x - 12, 204), 10, blue);
            }
            "Дождь"
        }
        "bell" => {
            let gold = Rgba([255, 211, 92, 255]);
            fill_circle(&mut image, 128, 58, 20, outline);
            fill_polygon(
                &mut image,
                &[
                    (67, 166),
                    (77, 95),
                    (101, 70),
                    (155, 70),
                    (179, 95),
                    (189, 166),
                    (203, 188),
                    (53, 188),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (80, 164),
                    (89, 101),
                    (108, 83),
                    (148, 83),
                    (167, 101),
                    (176, 164),
                    (185, 175),
                    (71, 175),
                ],
                gold,
            );
            fill_circle(&mut image, 128, 196, 24, outline);
            fill_circle(&mut image, 128, 196, 13, gold);
            "Звонок"
        }
        "camera" => {
            let body_color = Rgba([154, 183, 206, 255]);
            fill_rect(&mut image, 42, 78, 172, 124, outline);
            fill_rect(&mut image, 54, 90, 148, 100, body_color);
            fill_polygon(
                &mut image,
                &[(78, 78), (94, 55), (145, 55), (159, 78)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(91, 75), (101, 64), (139, 64), (147, 75)],
                body_color,
            );
            fill_circle(&mut image, 128, 140, 49, outline);
            fill_circle(&mut image, 128, 140, 36, Rgba([65, 91, 111, 255]));
            fill_circle(&mut image, 128, 140, 20, Rgba([104, 194, 255, 255]));
            fill_circle(&mut image, 181, 111, 8, Rgba([255, 225, 78, 255]));
            "Фото"
        }
        "heart_pulse" => {
            let scale = 0.83 + 0.18 * (phase * std::f64::consts::TAU).sin().abs();
            let r = (52.0 * scale) as i32;
            let spread = (40.0 * scale) as i32;
            let color = Rgba([255, 90, 125, 255]);
            fill_circle(&mut image, 128 - spread, 101, r + 9, outline);
            fill_circle(&mut image, 128 + spread, 101, r + 9, outline);
            fill_polygon(&mut image, &[(34, 108), (222, 108), (128, 229)], outline);
            fill_circle(&mut image, 128 - spread, 101, r, color);
            fill_circle(&mut image, 128 + spread, 101, r, color);
            fill_polygon(&mut image, &[(48, 109), (208, 109), (128, 211)], color);
            "Сердце бьётся"
        }
        "star_bounce" => {
            let y = 128 + (14.0 * (phase * std::f64::consts::TAU).sin()) as i32;
            let size = 90.0 + 10.0 * (phase * std::f64::consts::TAU).cos();
            fill_polygon(
                &mut image,
                &star_points(128, y, size + 12.0, (size + 12.0) * 0.50),
                outline,
            );
            fill_polygon(
                &mut image,
                &star_points(128, y, size, size * 0.50),
                Rgba([255, 201, 74, 255]),
            );
            "Прыгающая звезда"
        }
        "smile_blink" => {
            fill_circle(&mut image, 128, 128, 103, outline);
            fill_circle(&mut image, 128, 128, 91, yellow);
            let blink = (phase > 0.35 && phase < 0.56) || (phase > 0.68 && phase < 0.78);
            if blink {
                draw_thick_line(&mut image, (78, 106), (108, 106), 8, outline);
            } else {
                fill_circle(&mut image, 94, 105, 12, outline);
            }
            fill_circle(&mut image, 162, 105, 12, outline);
            draw_thick_line(&mut image, (91, 162), (126, 179), 9, outline);
            draw_thick_line(&mut image, (126, 179), (169, 152), 9, outline);
            "Подмигивание"
        }
        "party_wiggle" => {
            let wobble = (14.0 * (phase * std::f64::consts::TAU).sin()) as i32;
            fill_polygon(
                &mut image,
                &[(57 + wobble, 205), (104 + wobble, 61), (205 + wobble, 214)],
                outline,
            );
            fill_polygon(
                &mut image,
                &[(72 + wobble, 197), (108 + wobble, 79), (190 + wobble, 202)],
                Rgba([183, 136, 255, 255]),
            );
            fill_circle(
                &mut image,
                185 - wobble / 2,
                62,
                13,
                Rgba([83, 220, 232, 255]),
            );
            fill_circle(&mut image, 211 + wobble / 3, 104, 10, yellow);
            fill_circle(&mut image, 149, 38 + wobble / 4, 9, red);
            "Танцующая вечеринка"
        }
        "rocket_launch" => {
            let shift = (18.0 * (phase * std::f64::consts::TAU).sin()) as i32;
            let cy = -shift;
            fill_polygon(
                &mut image,
                &[
                    (128, 29 + cy),
                    (181, 91 + cy),
                    (164, 174 + cy),
                    (128, 203 + cy),
                    (92, 174 + cy),
                    (75, 91 + cy),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (128, 45 + cy),
                    (168, 96 + cy),
                    (154, 165 + cy),
                    (128, 187 + cy),
                    (102, 165 + cy),
                    (88, 96 + cy),
                ],
                Rgba([224, 235, 244, 255]),
            );
            fill_circle(&mut image, 128, 105 + cy, 24, outline);
            fill_circle(&mut image, 128, 105 + cy, 15, blue);
            fill_polygon(
                &mut image,
                &[(111, 190 + cy), (128, 236), (145, 190 + cy)],
                Rgba([255, 159, 45, 255]),
            );
            "Запуск ракеты"
        }
        "fire_flicker" => {
            let wobble = (9.0 * (phase * std::f64::consts::TAU).sin()) as i32;
            fill_polygon(
                &mut image,
                &[
                    (128 + wobble, 22),
                    (195 - wobble, 110),
                    (180, 205),
                    (128, 234),
                    (68, 204),
                    (56 + wobble, 123),
                    (100, 74),
                ],
                outline,
            );
            fill_polygon(
                &mut image,
                &[
                    (128 + wobble, 42),
                    (178 - wobble, 116),
                    (165, 194),
                    (128, 216),
                    (82, 190),
                    (72 + wobble, 132),
                    (111, 86),
                ],
                Rgba([255, 111, 54, 255]),
            );
            fill_polygon(
                &mut image,
                &[
                    (128 - wobble / 2, 100),
                    (157, 145),
                    (150, 187),
                    (128, 202),
                    (102, 180),
                    (101, 148),
                ],
                Rgba([255, 214, 71, 255]),
            );
            "Живой огонь"
        }
        "wave_wiggle" => {
            let wobble = (12.0 * (phase * std::f64::consts::TAU).sin()) as i32;
            fill_circle(&mut image, 125 + wobble / 4, 136, 75, outline);
            fill_circle(&mut image, 125 + wobble / 4, 136, 64, skin);
            for offset in [(-47, -73), (-17, -88), (14, -87), (44, -72)] {
                draw_thick_line(
                    &mut image,
                    (125 + offset.0 / 2 + wobble / 3, 122 + offset.1 / 3),
                    (125 + offset.0 + wobble, 122 + offset.1),
                    30,
                    outline,
                );
                draw_thick_line(
                    &mut image,
                    (125 + offset.0 / 2 + wobble / 3, 122 + offset.1 / 3),
                    (125 + offset.0 + wobble, 122 + offset.1),
                    19,
                    skin,
                );
            }
            draw_thick_line(
                &mut image,
                (178 + wobble / 4, 167),
                (219 + wobble, 138),
                31,
                outline,
            );
            draw_thick_line(
                &mut image,
                (178 + wobble / 4, 167),
                (216 + wobble, 142),
                19,
                skin,
            );
            "Машу рукой"
        }
        "wow_pulse" => {
            let pulse = 1.0 + 0.08 * (phase * std::f64::consts::TAU).sin();
            let outer = (103.0 * pulse) as i32;
            let inner = (91.0 * pulse) as i32;
            fill_circle(&mut image, 128, 128, outer, outline);
            fill_circle(&mut image, 128, 128, inner, yellow);
            fill_circle(&mut image, 92, 104, 13, outline);
            fill_circle(&mut image, 164, 104, 13, outline);
            fill_circle(&mut image, 128, 166, (30.0 * pulse) as i32, outline);
            fill_circle(
                &mut image,
                128,
                166,
                (18.0 * pulse) as i32,
                Rgba([103, 62, 55, 255]),
            );
            "Большое вау"
        }
        _ => return Err("Неизвестный встроенный стикер".to_owned()),
    };
    Ok((image, body))
}

pub(super) fn render_builtin_payload(
    sticker_id: &str,
) -> Result<(Vec<u8>, &'static str, &'static str), String> {
    match sticker_id {
        "heart" | "star" | "check" | "alert" | "smile" | "party" => {
            let (bytes, body) = render_builtin_sticker(sticker_id)?;
            Ok((bytes, body, "image/png"))
        }
        "heart_pulse" | "star_bounce" | "smile_blink" | "party_wiggle" | "rocket_launch"
        | "fire_flicker" | "wave_wiggle" | "wow_pulse" => {
            let mut encoded = Vec::new();
            let mut body = "Стикер";
            {
                let mut encoder = GifEncoder::new_with_speed(&mut encoded, 10);
                encoder
                    .set_repeat(Repeat::Infinite)
                    .map_err(|error| format!("Не удалось настроить GIF-стикер: {error}"))?;
                for index in 0..12 {
                    let phase = index as f64 / 12.0;
                    let (image, frame_body) = render_extended_shape(sticker_id, phase)?;
                    body = frame_body;
                    encoder
                        .encode_frame(Frame::from_parts(
                            image,
                            0,
                            0,
                            Delay::from_numer_denom_ms(85, 1),
                        ))
                        .map_err(|error| format!("Не удалось создать GIF-стикер: {error}"))?;
                }
            }
            Ok((encoded, body, "image/gif"))
        }
        _ => {
            let (image, body) = render_extended_shape(sticker_id, 0.0)?;
            let mut encoded = Cursor::new(Vec::new());
            DynamicImage::ImageRgba8(image)
                .write_to(&mut encoded, ImageFormat::Png)
                .map_err(|error| format!("Не удалось создать встроенный стикер: {error}"))?;
            Ok((encoded.into_inner(), body, "image/png"))
        }
    }
}
