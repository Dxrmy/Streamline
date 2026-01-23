```

BenchmarkDotNet v0.15.8, Linux Ubuntu 24.04.3 LTS (Noble Numbat)
Intel Xeon Processor 2.30GHz, 1 CPU, 4 logical and 4 physical cores
.NET SDK 8.0.122
  [Host]     : .NET 8.0.22 (8.0.22, 8.0.2225.52707), X64 RyuJIT x86-64-v3
  DefaultJob : .NET 8.0.22 (8.0.22, 8.0.2225.52707), X64 RyuJIT x86-64-v3


```
| Method           | Mean     | Error   | StdDev   | Gen0      | Gen1      | Gen2      | Allocated |
|----------------- |---------:|--------:|---------:|----------:|----------:|----------:|----------:|
| AnalyzeLargeFile | 432.2 ms | 8.62 ms | 22.25 ms | 9000.0000 | 8000.0000 | 3000.0000 | 330.46 MB |
