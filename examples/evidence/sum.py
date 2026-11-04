a, b = map(int, input().split())
print(((a + b + 2**31) % 2**32) - 2**31)
