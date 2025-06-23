import 'package:cached_network_image/cached_network_image.dart';
import 'package:card_swiper/swippable_cards/controller/card_swiper_controller.dart';
import 'package:card_swiper/swippable_cards/direction/card_swiper_direction.dart';
import 'package:card_swiper/swippable_cards/properties/allowed_swipe_direction.dart';
import 'package:card_swiper/swippable_cards/widget/card_swiper.dart';
import 'package:flutter/material.dart';

class CardSwippable extends StatefulWidget {
  const CardSwippable({super.key});

  @override
  State<CardSwippable> createState() => _CardSwippableState();
}

final CardSwiperController _swipperController = CardSwiperController();
int _currentIndex = 0;

class _CardSwippableState extends State<CardSwippable> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    // final IMAGES = [...?event?.galleryImages];
    // final IMAGES = [
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg',
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl-2.jpg',
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/puffin.jpg',
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg',
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl-2.jpg',
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/puffin.jpg',
    //   'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg',
    // ];
    final IMAGES = [
      'https://picsum.photos/id/1015/600/400',
      'https://picsum.photos/id/1025/600/400',
      'https://picsum.photos/id/1035/600/400',
      'https://picsum.photos/id/1045/600/400',
      'https://picsum.photos/id/1055/600/400',
      'https://picsum.photos/id/1065/600/400',
      'https://picsum.photos/id/1075/600/400',
    ];

    List<Widget> cards = IMAGES
        .map(
          (e) => GestureDetector(
            onTap: () => debugPrint(e),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              child: CachedNetworkImage(
                imageUrl: e,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
          ),
        )
        .toList();

    return Column(
      children: [
        Center(
          child: SizedBox(
            height: 420,
            width: 270,
            child: CardSwiper(
              controller: _swipperController,
              backCardOffset: const Offset(-20, -15),
              maxAngle: 1,
              isLoop: false,
              onSwipe:
                  (
                    int previousIndex,
                    int? currentIndex,
                    CardSwiperDirection direction,
                  ) {
                    setState(() {
                      _currentIndex = currentIndex ?? 0;
                    });
                    return true;
                  },
              duration: Duration(microseconds: 1000),
              allowedSwipeDirection: const AllowedSwipeDirection.only(
                right: true,
              ),
              cardsCount: cards.length,
              prebuiltCards: cards,
              numberOfCardsDisplayed: 3,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: _currentIndex == cards.length - 1
              ? GestureDetector(
                  onTap: () {
                    _swipperController.moveTo(2);
                    setState(() {
                      _currentIndex = 0;
                    });
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text('Restart'), const SizedBox(width: 8)],
                  ),
                )
              : Text('Swipe right to see more'),
        ),
      ],
    );
  }
}
