import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../card_animation.dart';
import '../controller/card_swiper_controller.dart';
import '../controller/controller_event.dart';
import '../direction/card_swiper_direction.dart';
import '../enums.dart';
import '../properties/allowed_swipe_direction.dart';
import '../typedefs.dart';
import '../utils/undoable.dart';

class CardSwiper extends StatefulWidget {
  final List<Widget>? prebuiltCards;

  final int cardsCount;

  final int initialIndex;

  final CardSwiperController? controller;

  final Duration duration;

  final double maxAngle;

  final AllowedSwipeDirection allowedSwipeDirection;

  final double thresholdPercentage;

  final double scale;

  final NullableCardBuilder? cardBuilder;

  final CardSwiperOnSwipe? onSwipe;

  final bool isLoop;

  final int numberOfCardsDisplayed;

  final Offset backCardOffset;

  const CardSwiper({
    required this.cardsCount,
    this.controller,
    this.initialIndex = 0,
    this.duration = const Duration(milliseconds: 200),
    this.maxAngle = 30,
    this.thresholdPercentage = 0.5,
    this.scale = 0.9,
    this.onSwipe,
    this.isLoop = true,
    this.numberOfCardsDisplayed = 2,
    this.backCardOffset = const Offset(0, 40),
    super.key,
    this.prebuiltCards,
    this.cardBuilder,
    required this.allowedSwipeDirection,
  }) : assert(
         maxAngle >= 0 && maxAngle <= 360,
         'maxAngle must be between 0 and 360',
       ),
       assert(
         thresholdPercentage > 0 && thresholdPercentage <= 1,
         'thresholdPercentage must be between 0 and 1',
       ),
       assert(scale >= 0 && scale <= 1, 'scale must be between 0 and 1'),
       assert(
         numberOfCardsDisplayed >= 1 && numberOfCardsDisplayed <= cardsCount,
         'you must display at least one card, and no more than [cardsCount]',
       ),
       assert(
         initialIndex >= 0 && initialIndex < cardsCount,
         'initialIndex must be between 0 and [cardsCount]',
       );

  @override
  State createState() => _CardSwiperState();
}

// part of 'card_swiper.dart';

class _CardSwiperState<T extends Widget> extends State<CardSwiper>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late CardAnimation _cardAnimation;
  late AnimationController _animationController;

  SwipeType _swipeType = SwipeType.none;
  CardSwiperDirection _detectedDirection = CardSwiperDirection.none;
  CardSwiperDirection _detectedHorizontalDirection = CardSwiperDirection.none;
  CardSwiperDirection _detectedVerticalDirection = CardSwiperDirection.none;
  bool _tappedOnTop = true;

  final _undoableIndex = Undoable<int?>(null);
  final Queue<CardSwiperDirection> _directionHistory = Queue();

  // --- ADDED FOR RESTART ANIMATION ---
  bool _isRestarting = false;
  double _restartAnimationProgress = 0.0;
  int? _restartFromIndex; // Track outgoing last card during restart
  // --- END ---

  int? get _currentIndex => _undoableIndex.state;

  int? get _nextIndex => getValidIndexOffset(1);

  bool get _canSwipe => _currentIndex != null;

  StreamSubscription<ControllerEvent>? controllerSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _undoableIndex.state = widget.initialIndex;

    controllerSubscription = widget.controller?.events.listen(
      _controllerListener,
    );

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500), // Longer duration for smoother animation
      vsync: this,
    )..addListener(_animationListener)
      ..addStatusListener(_animationStatusListener);

    _cardAnimation = CardAnimation(
      animationController: _animationController,
      maxAngle: widget.maxAngle,
      initialScale: widget.scale,
      allowedSwipeDirection: widget.allowedSwipeDirection,
      initialOffset: widget.backCardOffset,
      onSwipeDirectionChanged: onSwipeDirectionChanged,
    );
  }

  void onSwipeDirectionChanged(CardSwiperDirection direction) {
    switch (direction) {
      case CardSwiperDirection.none:
        _detectedVerticalDirection = direction;
        _detectedHorizontalDirection = direction;
      case CardSwiperDirection.right:
      case CardSwiperDirection.left:
        _detectedHorizontalDirection = direction;
      case CardSwiperDirection.top:
      case CardSwiperDirection.bottom:
        _detectedVerticalDirection = direction;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    controllerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // --- RESTART ANIMATION: render both outgoing last card and incoming new stack ---
        if (_isRestarting && _restartFromIndex != null) {
          final List<Widget> stackChildren = [];

          // Outgoing last card animating to stacked position
          stackChildren.add(_outgoingLastCard(constraints, _restartFromIndex!));

          // Always animate exactly the first three cards (0, 1, 2) from right, in reverse order for correct stacking
          for (int i = 2; i >= 0; i--) {
            if (i < widget.cardsCount) {
              stackChildren.add(_incomingRestartCard(constraints, i));
            }
          }

          // Stacked cards behind (for completeness, not animated)
          for (int i = 3; i < widget.cardsCount; i++) {
            stackChildren.add(_stackedBackItem(constraints, i));
          }

          return Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: stackChildren,
          );
        }
        // --- END RESTART ANIMATION ---

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            // First render all stacked cards that are not visible
            ...List.generate(
              widget.cardsCount - widget.numberOfCardsDisplayed,
              (index) {
                final actualIndex = index + widget.numberOfCardsDisplayed;
                return _stackedBackItem(constraints, actualIndex);
              },
            ),
            // Then render visible cards on top
            ...List.generate(widget.numberOfCardsDisplayed, (index) {
              if (index == 0) return _frontItem(constraints);
              return _backItem(constraints, index);
            }).reversed.toList(),
          ],
        );
      },
    );
  }

  Widget _frontItem(BoxConstraints constraints) {
    final card = widget.prebuiltCards != null
        ? widget.prebuiltCards![_currentIndex!]
        : widget.cardBuilder!(
            context,
            _currentIndex!,
            (100 *
                    _cardAnimation.left /
                    (MediaQuery.of(context).size.width *
                        widget.thresholdPercentage))
                .ceil(),
            (100 *
                    _cardAnimation.top /
                    (MediaQuery.of(context).size.width *
                        widget.thresholdPercentage))
                .ceil(),
          );

    final screenWidth = MediaQuery.of(context).size.width;
    // --- RESTART ANIMATION LOGIC ---
    if (_isRestarting && _currentIndex == 0) {
      // Animate from right edge to stack position
      final startLeft = screenWidth;
      final endLeft = 0.0;
      final currentLeft = startLeft + (endLeft - startLeft) * _restartAnimationProgress;
      final currentAngle = 0.0; // No angle for front card
      return Positioned(
        left: currentLeft,
        top: 0.0,
        child: Transform.rotate(
          alignment: Alignment.bottomLeft,
          angle: currentAngle,
          child: ConstrainedBox(constraints: constraints, child: card),
        ),
      );
    }
    // --- END RESTART LOGIC ---

    // If we're moving back to index 0, animate from right (legacy logic)
    final isMovingBack = _currentIndex == widget.cardsCount - 1 && _undoableIndex.state == 0;
    final startLeft = isMovingBack ? screenWidth : _cardAnimation.left;
    final endLeft = isMovingBack ? 0 : _cardAnimation.left;
    final animationProgress = isMovingBack ? _animationController.value : 1.0;
    final currentLeft = startLeft + (endLeft - startLeft) * animationProgress;
    final currentAngle = _cardAnimation.angle * animationProgress;

    return Positioned(
      left: currentLeft,
      top: _cardAnimation.top,
      child: GestureDetector(
        child: Transform.rotate(
          alignment: Alignment.bottomLeft,
          angle: currentAngle,
          child: ConstrainedBox(constraints: constraints, child: card),
        ),
        onPanStart: (tapInfo) {
          final renderBox = context.findRenderObject()! as RenderBox;
          final position = renderBox.globalToLocal(tapInfo.globalPosition);

          if (position.dy < renderBox.size.height / 2) _tappedOnTop = true;
        },
        onPanUpdate: (tapInfo) {
          final isLastCard =
              _currentIndex == widget.cardsCount - 1 && !widget.isLoop;

          if (!isLastCard) {
            setState(
              () => _cardAnimation.update(
                tapInfo.delta.dx,
                tapInfo.delta.dy,
                _tappedOnTop,
              ),
            );
          }
        },
        onPanEnd: (tapInfo) {
          if (_canSwipe) {
            _tappedOnTop = true;
            _onEndAnimation();
          }
        },
      ),
    );
  }

  Widget _backItem(BoxConstraints constraints, int index) {
    final validIndex = getValidIndexOffset(index);
    if (validIndex == null) return const SizedBox.shrink();

    final card = widget.prebuiltCards != null
        ? widget.prebuiltCards![validIndex]
        : widget.cardBuilder!(context, validIndex, 0, 0);

    final screenWidth = MediaQuery.of(context).size.width;
    // --- RESTART ANIMATION LOGIC ---
    if (_isRestarting && validIndex < 3) {
      // Animate from right edge to stack position for the first 3 cards
      final baseOffset = index * 20.0;
      final startLeft = screenWidth;
      final endLeft = baseOffset;
      final currentLeft = startLeft + (endLeft - startLeft) * _restartAnimationProgress;
      final baseAngle = -(5.0 * index) * math.pi / 180;
      final currentAngle = baseAngle * _restartAnimationProgress;
      return Positioned(
        top: 0.0,
        left: currentLeft,
        child: Transform.rotate(
          alignment: Alignment.bottomLeft,
          angle: currentAngle,
          child: ConstrainedBox(constraints: constraints, child: card),
        ),
      );
    }
    // --- END RESTART LOGIC ---

    // Only animate the first two back cards
    if (index <= 2) {
      final isMovingBack = _currentIndex == widget.cardsCount - 1 && _undoableIndex.state == 0;
      final baseAngle = -(5.0 * index) * math.pi / 180;
      final targetAngle = -(5.0 * (index - 1)) * math.pi / 180;
      final baseOffset = index * 20.0;
      final targetOffset = (index - 1) * 20.0;
      final swipeProgress = _cardAnimation.left.abs() / (screenWidth * widget.thresholdPercentage);
      final clampedProgress = swipeProgress.clamp(0.0, 1.0);
      final currentOffset = baseOffset + (targetOffset - baseOffset) * clampedProgress;
      final currentAngle = baseAngle + (targetAngle - baseAngle) * clampedProgress;
      return Positioned(
        top: 0,
        left: currentOffset,
        child: Transform.rotate(
          alignment: Alignment.bottomLeft,
          angle: currentAngle,
          child: ConstrainedBox(constraints: constraints, child: card),
        ),
      );
    } else {
      // For cards after index 2, keep them in fixed position
      return Positioned(
        top: 0,
        left: index * 20.0,
        child: Transform.rotate(
          alignment: Alignment.bottomLeft,
          angle: -(5.0 * index) * math.pi / 180,
          child: ConstrainedBox(constraints: constraints, child: card),
        ),
      );
    }
  }

  Widget _stackedBackItem(BoxConstraints constraints, int index) {
    final validIndex = getValidIndexOffset(index);
    if (validIndex == null) return const SizedBox.shrink();

    final card = widget.prebuiltCards != null
        ? widget.prebuiltCards![validIndex]
        : widget.cardBuilder!(context, validIndex, 0, 0);

    // Keep stacked cards in fixed position behind the last visible card
    final lastVisibleIndex = widget.numberOfCardsDisplayed - 1;
    final baseAngle = -(5.0 * lastVisibleIndex) * math.pi / 180;
    final baseOffset = lastVisibleIndex * 20.0;

    // Only show and position cards that are not part of the visible cards
    if (index >= widget.numberOfCardsDisplayed) {
      return Positioned(
        top: 0,
        left: baseOffset,
        child: Transform.rotate(
          alignment: Alignment.bottomLeft,
          angle: baseAngle,
          child: ConstrainedBox(constraints: constraints, child: card),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // --- Outgoing last card during restart ---
  Widget _outgoingLastCard(BoxConstraints constraints, int lastIndex) {
    final card = widget.prebuiltCards != null
        ? widget.prebuiltCards![lastIndex]
        : widget.cardBuilder!(context, lastIndex, 0, 0);
    final lastVisibleIndex = widget.numberOfCardsDisplayed - 1;
    final startLeft = 0.0;
    final endLeft = lastVisibleIndex * 20.0;
    final curveValue = Curves.easeOutCubic.transform(_restartAnimationProgress);
    final currentLeft = startLeft + (endLeft - startLeft) * curveValue;
    final startAngle = 0.0;
    final endAngle = -(5.0 * lastVisibleIndex) * math.pi / 180;
    final currentAngle = startAngle + (endAngle - startAngle) * curveValue;
    return Positioned(
      left: currentLeft,
      top: 0.0,
      child: Transform.rotate(
        alignment: Alignment.bottomLeft,
        angle: currentAngle,
        child: ConstrainedBox(constraints: constraints, child: card),
      ),
    );
  }

  // --- Incoming new stack cards during restart ---
  Widget _incomingRestartCard(BoxConstraints constraints, int index) {
    final validIndex = index;
    if (validIndex >= widget.cardsCount) return const SizedBox.shrink();
    final card = widget.prebuiltCards != null
        ? widget.prebuiltCards![validIndex]
        : widget.cardBuilder!(context, validIndex, 0, 0);
    final screenWidth = MediaQuery.of(context).size.width;
    final baseOffset = index * 20.0;
    final startLeft = screenWidth;
    final endLeft = baseOffset;
    final curveValue = Curves.easeOutCubic.transform(_restartAnimationProgress);
    final currentLeft = startLeft + (endLeft - startLeft) * curveValue;
    final baseAngle = -(5.0 * index) * math.pi / 180;
    final currentAngle = baseAngle * curveValue;
    return Positioned(
      top: 0.0,
      left: currentLeft,
      child: Transform.rotate(
        alignment: Alignment.bottomLeft,
        angle: currentAngle,
        child: ConstrainedBox(constraints: constraints, child: card),
      ),
    );
  }

  void _controllerListener(ControllerEvent event) {
    return switch (event) {
      ControllerSwipeEvent(:final direction) => _swipe(direction),
      // ControllerUndoEvent() => _undo(),
      ControllerMoveEvent(:final index) => _moveTo(index),
    };
  }

  void _animationListener() {
    if (_animationController.status == AnimationStatus.forward) {
      setState(() {
        _cardAnimation.sync();
      });
    }
  }

  void _animationStatusListener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      switch (_swipeType) {
        case SwipeType.swipe:
          _handleCompleteSwipe();
        case SwipeType.move:
          // Handle move completion
          setState(() {
            _undoableIndex.state = _undoableIndex.state;
            _cardAnimation.reset();
          });
        default:
          break;
      }

      _reset();
    }
  }

  Future<void> _handleCompleteSwipe() async {
    final isLastCard = _currentIndex! == widget.cardsCount - 1;

    final nextIndex = _nextIndex;

    final shouldCancelSwipe =
        await widget.onSwipe?.call(
          _currentIndex!,
          nextIndex,
          _detectedDirection,
        ) ==
        false;

    if (shouldCancelSwipe) {
      _goBack();
      return;
    }

    // 👇 Prevent swipe if it's the last card and not looping
    if (!widget.isLoop && isLastCard) {
      _goBack();
      return;
    }

    _undoableIndex.state = nextIndex;
    _directionHistory.add(_detectedDirection);

    if (nextIndex == null && !widget.isLoop) {
      // widget.onEnd?.call();
    }
  }

  void _reset() {
    onSwipeDirectionChanged(CardSwiperDirection.none);
    _detectedDirection = CardSwiperDirection.none;
    setState(() {
      _animationController.reset();
      _cardAnimation.reset();
      _swipeType = SwipeType.none;
    });
  }

  void _onEndAnimation() {
    final direction = _getEndAnimationDirection();
    final isValidDirection = _isValidDirection(direction);

    if (isValidDirection) {
      _swipe(direction);
    } else {
      _goBack();
    }
  }

  CardSwiperDirection _getEndAnimationDirection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * widget.thresholdPercentage;

    if (_cardAnimation.left.abs() > threshold) {
      return _cardAnimation.left.isNegative
          ? CardSwiperDirection.left
          : CardSwiperDirection.right;
    }
    if (_cardAnimation.top.abs() > threshold) {
      return _cardAnimation.top.isNegative
          ? CardSwiperDirection.top
          : CardSwiperDirection.bottom;
    }
    return CardSwiperDirection.none;
  }

  bool _isValidDirection(CardSwiperDirection direction) {
    return switch (direction) {
      CardSwiperDirection.left => widget.allowedSwipeDirection.left,
      CardSwiperDirection.right => widget.allowedSwipeDirection.right,
      CardSwiperDirection.top => widget.allowedSwipeDirection.up,
      CardSwiperDirection.bottom => widget.allowedSwipeDirection.down,
      _ => false,
    };
  }

  void _swipe(CardSwiperDirection direction) {
    if (_currentIndex == null) return;
    _swipeType = SwipeType.swipe;
    _detectedDirection = direction;

    // Calculate the final position based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final finalPosition = direction == CardSwiperDirection.right
        ? screenWidth *
              1.2 // Move further right for smooth exit
        : -screenWidth * 1.2; // Move further left for smooth exit

    // Create smooth animations with proper curves
    final leftAnimation =
        Tween<double>(begin: _cardAnimation.left, end: finalPosition).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    final angleAnimation =
        Tween<double>(
          begin: _cardAnimation.angle,
          end:
              (finalPosition / screenWidth) * widget.maxAngle * (math.pi / 180),
        ).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    // Add listeners for smooth updates
    leftAnimation.addListener(() {
      if (!mounted) return;
      setState(() {
        _cardAnimation.left = leftAnimation.value;
        _cardAnimation.angle = angleAnimation.value;
      });
    });

    // Reset and start animation
    _animationController.reset();
    _animationController.forward();
  }

  void _goBack() {
    _swipeType = SwipeType.back;

    // Create smooth animations with proper curves
    final leftAnimation = Tween<double>(begin: _cardAnimation.left, end: 0)
        .animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    final angleAnimation = Tween<double>(begin: _cardAnimation.angle, end: 0)
        .animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    final topAnimation = Tween<double>(begin: _cardAnimation.top, end: 0)
        .animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    // Add listeners for smooth updates
    leftAnimation.addListener(() {
      if (!mounted) return;
      setState(() {
        _cardAnimation.left = leftAnimation.value;
        _cardAnimation.angle = angleAnimation.value;
        _cardAnimation.top = topAnimation.value;
      });
    });

    // Reset and start animation
    _animationController.reset();
    _animationController.forward();
  }

  // void _undo() {
  //   if (_directionHistory.isEmpty) return;
  //   if (_undoableIndex.previousState == null) return;

  //   final direction = _directionHistory.last;
  //   final shouldCancelUndo = widget.onUndo?.call(
  //         _currentIndex,
  //         _undoableIndex.previousState!,
  //         direction,
  //       ) ==
  //       false;

  //   if (shouldCancelUndo) {
  //     return;
  //   }

  //   _undoableIndex.undo();
  //   _directionHistory.removeLast();
  //   _swipeType = SwipeType.undo;
  //   _cardAnimation.animateUndo(context, direction);
  // }

  void _moveTo(int index) {
    if (index < 0 || index >= widget.cardsCount) return;
    if (_currentIndex != widget.cardsCount - 1) return; // Only allow when at last card

    // --- RESTART ANIMATION LOGIC ---
    if (index == 0) {
      setState(() {
        _isRestarting = true;
        _restartAnimationProgress = 0.0;
        _restartFromIndex = _currentIndex; // Track outgoing last card
      });
      _animationController.duration = const Duration(milliseconds: 500);
      _animationController.removeListener(_restartListener);
      _animationController.addListener(_restartListener);
      _animationController.reset();
      _animationController.forward();
      return;
    }
    // --- END RESTART LOGIC ---

    // Set the swipe type to indicate we're doing a move animation
    _swipeType = SwipeType.move;

    // Set a longer duration for smoother animation
    _animationController.duration = const Duration(milliseconds: 500);

    // Calculate the target position for the last card (stacked position)
    final lastVisibleIndex = widget.numberOfCardsDisplayed - 1;
    final targetAngle = -(5.0 * lastVisibleIndex) * math.pi / 180; // Same angle as stacked card
    final targetOffset = lastVisibleIndex * 10.0; // Same offset as stacked card

    // Create smooth animations with proper curves
    final leftAnimation = Tween<double>(begin: _cardAnimation.left, end: targetOffset).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    final angleAnimation = Tween<double>(begin: _cardAnimation.angle, end: targetAngle).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    final topAnimation = Tween<double>(begin: _cardAnimation.top, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    // Add listeners for smooth updates
    leftAnimation.addListener(() {
      if (!mounted) return;
      setState(() {
        _cardAnimation.left = leftAnimation.value;
        _cardAnimation.angle = angleAnimation.value;
        _cardAnimation.top = topAnimation.value;
      });
    });

    // Reset and start animation
    _animationController.reset();
    _animationController.forward().then((_) {
      setState(() {
        _undoableIndex.state = index;
        _cardAnimation.reset();
      });
    });
  }

  // --- RESTART ANIMATION LISTENER ---
  void _restartListener() {
    if (!_isRestarting) return;
    setState(() {
      _restartAnimationProgress = _animationController.value;
    });
    if (_animationController.isCompleted) {
      _animationController.removeListener(_restartListener);
      setState(() {
        _isRestarting = false;
        _restartAnimationProgress = 0.0;
        _restartFromIndex = null;
        _undoableIndex.state = 0;
        _cardAnimation.reset();
      });
    }
  }
  // --- END RESTART ANIMATION LISTENER ---

  void _onSwipeRight() {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    // Animate the current top card off screen
    _cardAnimation.animate(context, CardSwiperDirection.right);
    _animationController.forward().then((_) {
      setState(() {
        _undoableIndex.state = _currentIndex! + 1;
        _cardAnimation.reset();
      });
    });
  }

  void _onSwipeLeft() {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    // Animate the current top card off screen
    _cardAnimation.animate(context, CardSwiperDirection.left);
    _animationController.forward().then((_) {
      setState(() {
        _undoableIndex.state = _currentIndex! + 1;
        _cardAnimation.reset();
      });
    });
  }

  void _onSwipeTop() {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    // Animate the current top card off screen
    _cardAnimation.animate(context, CardSwiperDirection.top);
    _animationController.forward().then((_) {
      setState(() {
        _undoableIndex.state = _currentIndex! + 1;
        _cardAnimation.reset();
      });
    });
  }

  void _onSwipeBottom() {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    // Animate the current top card off screen
    _cardAnimation.animate(context, CardSwiperDirection.bottom);
    _animationController.forward().then((_) {
      setState(() {
        _undoableIndex.state = _currentIndex! + 1;
        _cardAnimation.reset();
      });
    });
  }

  void _onSwipeCancel() {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    // Animate the current top card back to center
    _cardAnimation.animateBack(context);
    _animationController.forward().then((_) {
      setState(() {
        _cardAnimation.reset();
      });
    });
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate swipe progress
    final horizontalProgress = details.delta.dx / screenWidth;
    final verticalProgress = details.delta.dy / screenHeight;

    // Update card position and angle based on swipe direction
    if (horizontalProgress.abs() > verticalProgress.abs()) {
      // Horizontal swipe
      _cardAnimation.left += details.delta.dx;
      _cardAnimation.angle = (_cardAnimation.left / screenWidth) * 30 * math.pi / 180;
    } else {
      // Vertical swipe
      _cardAnimation.top += details.delta.dy;
      _cardAnimation.angle = (_cardAnimation.top / screenHeight) * 30 * math.pi / 180;
    }

    setState(() {});
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate swipe velocity and position
    final velocity = details.velocity.pixelsPerSecond;
    final position = _cardAnimation.left.abs() > _cardAnimation.top.abs()
        ? _cardAnimation.left / screenWidth
        : _cardAnimation.top / screenHeight;

    // Determine if swipe threshold is met
    final threshold = 0.3;
    final isSwipeRight = _cardAnimation.left > 0 && (position > threshold || velocity.dx > 500);
    final isSwipeLeft = _cardAnimation.left < 0 && (position.abs() > threshold || velocity.dx < -500);
    final isSwipeTop = _cardAnimation.top < 0 && (position.abs() > threshold || velocity.dy < -500);
    final isSwipeBottom = _cardAnimation.top > 0 && (position > threshold || velocity.dy > 500);

    if (isSwipeRight) {
      _onSwipeRight();
    } else if (isSwipeLeft) {
      _onSwipeLeft();
    } else if (isSwipeTop) {
      _onSwipeTop();
    } else if (isSwipeBottom) {
      _onSwipeBottom();
    } else {
      _onSwipeCancel();
    }
  }

  void _onSwipeStart(DragStartDetails details) {
    if (_currentIndex! >= widget.cardsCount - 1) return;

    _cardAnimation.reset();
    _animationController.reset();
  }

  int numberOfCardsOnScreen() {
    if (widget.isLoop) {
      return widget.numberOfCardsDisplayed;
    }
    if (_currentIndex == null) {
      return 0;
    }

    return math.min(
      widget.numberOfCardsDisplayed,
      widget.cardsCount - _currentIndex!,
    );
  }

  int? getValidIndexOffset(int index) {
    final currentIndex = _undoableIndex.state;
    if (currentIndex == null) return null;

    // Calculate the actual index based on the current position
    final validIndex = currentIndex + index;
    
    // If we're swiping and showing the next card
    if (_cardAnimation.left.abs() > 0 && index == 0) {
      // Show the next card in sequence (card 3 when swiping card 0)
      final nextIndex = currentIndex + widget.numberOfCardsDisplayed;
      if (nextIndex < widget.cardsCount) {
        return nextIndex;
      }
    }
    
    // For stacked cards, ensure we don't show the last card during swipe
    if (index >= widget.numberOfCardsDisplayed) {
      final stackedIndex = currentIndex + widget.numberOfCardsDisplayed;
      if (stackedIndex >= widget.cardsCount) return null;
      return stackedIndex;
    }
    
    if (validIndex >= widget.cardsCount) return null;
    return validIndex;
  }

  void _updateBackCardsAngles() {
    // This method will be called during animation to update back card angles
    setState(() {
      // The setState here will trigger a rebuild of the back cards with new angles
    });
  }
}

extension NumberExtension on num {
  bool isBetween(num from, num to) {
    return from <= this && this <= to;
  }
}
