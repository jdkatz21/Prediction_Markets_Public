import React, { useRef, useEffect } from 'react';
import { animated, useSpring } from '@react-spring/web';

export default function AnimatedBar({ x, y, width, height, fill }) {
  const prev = useRef({ y, height });

  const spring = useSpring({
    from: { y: prev.current.y, height: prev.current.height },
    to: { y, height },
    config: { tension: 180, friction: 22 },
  });

  useEffect(() => {
    prev.current = { y, height };
  }, [y, height]);

  return (
    <animated.rect
      x={x}
      width={width}
      fill={fill}
      y={spring.y}
      height={spring.height}
    />
  );
}