#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <signal.h> 

#define MAX_LENGTH 200

// 定义全局变量
char thermal_file[MAX_LENGTH] = "/sys/devices/virtual/thermal/thermal_zone0/temp";
char fan_file[MAX_LENGTH] = "/sys/devices/virtual/thermal/cooling_device0/cur_state";
char thresholds_str[MAX_LENGTH] = "100,90,80,75,60,65,60,50,45";
char speeds_str[MAX_LENGTH] = "255,220,185,150,115,95,80,60,30";
char debug_mode = '0';

/**
 * 逗号分隔的转数组
 */
void string_to_array(char* str ,int* array ,size_t* len) {
    char* token = strtok(str ,",");
    *len = 0;
    while (token != NULL) {
        array[*len] = atoi(token);
        ( *len )++;
        token = strtok(NULL ,",");
    }
}

/**
 * 底层读文件
 */
static int read_file(const char* path ,char* result ,size_t size) {
    FILE* fp;
    char* line = NULL;
    size_t len = 0;
    ssize_t read;

    fp = fopen(path ,"r");
    if (fp == NULL)
        return -1;

    if (( read = getline(&line ,&len ,fp) ) != -1) {
        if (size != 0)
            memcpy(result ,line ,size);
        else
            memcpy(result ,line ,read - 1);
    }

    fclose(fp);
    if (line)
        free(line);
    return 0;
}

/**
 * 底层写文件
 */
static size_t write_file(const char* path ,char* buf ,size_t len) {
    FILE* fp = NULL;
    size_t size = 0;
    fp = fopen(path ,"w+");
    if (fp == NULL) {
        return 0;
    }
    size = fwrite(buf ,len ,1 ,fp);
    fclose(fp);
    return size;
}

/**
 * 读取温度
 */
int get_temperature(char* thermal_file) {
    char buf[8] = { 0 };
    if (read_file(thermal_file ,buf ,0) == 0) {
        return atoi(buf) / 1000;
    }
    return -1;
}

/**
 * 读取风扇速度
 */
int get_fanspeed(char* fan_file) {
    char buf[8] = { 0 };
    if (read_file(fan_file ,buf ,0) == 0) {
        return atoi(buf);
    }
    return -1;
}

/**
 * 设置风扇转速
 */
int set_fanspeed(int fan_speed ,char* fan_file) {
    char buf[8] = { 0 };
    sprintf(buf ,"%d\n" ,fan_speed);
    return write_file(fan_file ,buf ,strlen(buf));
}

/**
 * 计算风扇转速
 */
int calculate_speed(int temperature ,int* thresholds ,size_t len_t ,int* speeds ,size_t len_s) {
    int fan_speed = 0;
    for (int i = 0; i < len_t; i++) {
        if (temperature > thresholds[i]) {
            fan_speed = i >= len_s ? speeds[len_s - 1] : speeds[i];
        } else break;
    }
    return fan_speed;
}

/**
 * 判断文件是否存在方法
 */
static int file_exist(const char* name) {
    struct stat buffer;
    return stat(name ,&buffer);
}

/**
 * 排序函数
*/
int cmp(const void* a ,const void* b) {
    return *( int* )a - *( int* )b;
}

/**
 *  信号处理函数
 */
void handle_termination(int signum) {
    // 设置风扇转速为 0
    set_fanspeed(0 ,fan_file);
    exit(EXIT_SUCCESS); // 优雅地退出程序
}

/**
 * 注册信号处理函数
 */
void register_signal_handlers( ) {
    struct sigaction sa;
    memset(&sa ,0 ,sizeof(sa));
    sa.sa_handler = handle_termination;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT ,&sa ,NULL);
    sigaction(SIGTERM ,&sa ,NULL);
}

/**
 * 主函数
 */
int main(int argc ,char* argv[ ]) {
    int thresholds[MAX_LENGTH] ,speeds[MAX_LENGTH];
    size_t len_t = 0 ,len_s = 0;

    // 解析命令行选项
    int opt;
    while (( opt = getopt(argc ,argv ,"t:f:s:e:d:") ) != -1) {
        switch (opt) {
            case 't':
                snprintf(thermal_file ,sizeof(thermal_file) ,"%s" ,optarg);
                break;
            case 'f':
                snprintf(fan_file ,sizeof(fan_file) ,"%s" ,optarg);
                break;
            case 's':
                snprintf(speeds_str ,sizeof(speeds_str) ,"%s" ,optarg);
                break;
            case 'e':
                snprintf(thresholds_str ,sizeof(thresholds_str) ,"%s" ,optarg);
                break;
            case 'd':
                snprintf(&debug_mode ,sizeof(debug_mode) ,"%s" ,optarg);
                break;
            default:
                fprintf(stderr ,"Usage: %s [-t thermal_file] [-f fan_file] [-s speeds] [-e thresholds]\n" ,argv[0]);
                exit(EXIT_FAILURE);
        }
    }
    // 检测虚拟文件是否存在
    if (file_exist(fan_file) != 0 || file_exist(thermal_file) != 0) {
        fprintf(stderr ,"File: '%s' or '%s' not exist\n" ,fan_file ,thermal_file);
        exit(EXIT_FAILURE);
    }

    // 字符串转数组
    string_to_array(thresholds_str ,thresholds ,&len_t);
    string_to_array(speeds_str ,speeds ,&len_s);

    // 从大到小排序
    qsort(thresholds ,len_t ,sizeof(int) ,cmp);
    qsort(speeds ,len_s ,sizeof(int) ,cmp);

    // 注册退出信号
    register_signal_handlers( );

    // 监控风扇
    while (1) {
        int temperature = get_temperature(thermal_file);
        // 有效温度时设置风扇速度
        if (temperature > 0) {
            int fan_speed = calculate_speed(temperature ,thresholds ,len_t ,speeds ,len_s);
            set_fanspeed(fan_speed ,fan_file);
        }
        if (debug_mode != '0') {
            fprintf(stdout ,"Temperature: %d°C, Fan Speed: %d\n" ,get_temperature(thermal_file) ,get_fanspeed(fan_file));
        }
        sleep(5);
    }
    return 0;
}