#include <iostream>

using namespace std;

const double PI = 3.14;


// 定义抽象基类 Shape

class Shape

{

public:

    virtual void print() = 0; // 纯虚函数，用于打印形状信息

    virtual ~Shape(){} // 虚析构函数，确保派生类析构时能正确调用

};


// 定义二维形状类，继承自 Shape

class TwoDimensionalShape: public Shape

{

public:

    virtual double getArea() = 0; // 纯虚函数，用于获取二维形状的面积

    void print() // 实现打印函数

    {

        cout << "TwoDimensionalShape, area=" << getArea() << endl; // 打印面积

    }

};

// 定义三维形状类，继承自 Shape

class ThreeDimensionalShape: public Shape

{

public:

    virtual double getVolume() = 0; // 纯虚函数，用于获取三维形状的体积

    void print() // 实现打印函数

    {

        cout << "ThreeDimensionalShape, volume=" << getVolume() << endl; // 打印体积

    }

};


// 定义圆形类，继承自二维形状类
class Circle : public TwoDimensionalShape

{

private:

    double radius; // 半径

public:

    Circle(double r) : radius(r) {} // 构造函数，初始化半径

    double getArea() { return PI * radius * radius; } // 面积 = PI * r^2

};


// 定义正方形类，继承自二维形状类
class Square : public TwoDimensionalShape

{

private:

    double side; // 边长

public:

    Square(double s) : side(s) {} // 构造函数，初始化边长

    double getArea() { return side * side; } // 面积 = 边长^2

};


// 定义正立方体类，继承自三维形状类
class Cube : public ThreeDimensionalShape

{

private:

    double side; // 棱长

public:

    Cube(double s) : side(s) {} // 构造函数，初始化棱长

    double getVolume() { return side * side * side; } // 体积 = 棱长^3

};



int main()

{

    Shape *shape[3]; // 定义一个 Shape 类型的指针数组，用于存储不同形状对象的指针

    shape[0] = new Circle(1.5); // 创建一个半径为 1.5 的圆形对象

    shape[1] = new Cube(1.2);     // 创建一个边长为 1.2 的立方体对象

    shape[2] =  new Square(2);   // 创建一个边长为 2 的正方形对象



    for(int i = 0; i < 3; i++)

        shape[i]->print(); // 调用每个形状对象的 print 函数



   for(int i = 0; i < 3; i++)

        delete shape[i]; // 回收每个元素内存



    return 0; // 程序结束

}
