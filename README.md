### Processor-Cache  
A Verilog implementation of a data and instruction cache processor, Auxillary modules such as memory and testbench initialization were created.

The data cache implements a 32 KiB, 4-way set associative, 2-word block cache with 32 bit words.
The instruction cache implements a 16 KiB, 2-way set associative, 1-word block cache with 32 bit words.
Both are write-back, write-allocate caches with an LRU replacement policy.

The Finite State Machine(FSM) is implemented to Controls the entire cache operation and HIT/MISS detection.

### FSM Flow :
1.IDLE
    Waiting for request from CPU
2.COMPARE TAG
    Check hit/miss 
3. HIT
    Directly:
          Read data (for load)
          Write data (for store)
     Fast --> 1 cycle
 4. MISS
       Now FSM takes control 
 5. ALLOCATE / READ FROM MEMORY
       Fetch block from main memory
 6. WRITE BACK (if dirty)
       If it's a write-back cache and block is dirty:
       Write old data to memory first
 7. UPDATE CACHE
       Store new block
       Update tag, valid, dirty bits
 8. COMPLETE
       Send data to CPU.
       
- Hit/Miss detection is combinational, while FSM controls the sequence of operations.

### Address Breakdown
Each memory address is divided into:
- Tag
- Index
- Offset


HIT/MISS compares:
        Tag from CPU address
        Tag stored in cache
        Valid bit 


##  I-Cache (Instruction Cache)

- Read-only cache
- Handles instruction fetch requests
- No write operations
- Simplified FSM (no dirty handling)


	Address inputs:
		19 tag bits
		11 index bits
		2  offset bits

	Cache line:
		1  LRU bit
		1  valid bit
		1  dirty bit
		18 tag bits
		32 data bits
		
## D-Cache (Data Cache)

- Supports both **load and store operations**
- Includes write handling logic
- Uses dirty bit (if write-back policy is implemented)


	Address inputs:
		19 tag bits
		10 index bits
		3  offset bits

	Cache line:
		2  LRU bits
		1  valid bit
		1  dirty bit
		19 tag bits
		64 data bits


## Verification

### Tools Used:
- Icarus Verilog (`iverilog`)
- GTKWave

### Testing Includes:
- Hit scenario validation
- Miss scenario handling
- Cache update verification
- FSM state transitions
- Read/Write correctness


## Observations in Waveform

- rd1 / rd2 outputs verification
- Hit/Miss signal transitions
- FSM state changes
- Memory read/write operations
- Cache line updates
