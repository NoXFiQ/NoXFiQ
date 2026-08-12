import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/location_service.dart';
import '../models/product_model.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/category_filter.dart';
import '../widgets/premium_banner.dart';
import '../utils/constants.dart';
import '../utils/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final PageController _pageController = PageController();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final productService = context.read<ProductService>();
    await productService.loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer3<AuthService, ProductService, LocationService>(
        builder: (context, authService, productService, locationService, child) {
          return CustomScrollView(
            slivers: [
              // App Bar
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: AppColors.primary,
                flexibleSpace: FlexibleSpaceBar(
                  title: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localization.appName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (authService.currentUser?.location != null)
                        Text(
                          '${authService.currentUser!.location!.district}, ${authService.currentUser!.location!.region}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.notifications, color: Colors.white),
                    onPressed: () {
                      // Navigate to notifications
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.account_circle, color: Colors.white),
                    onPressed: () {
                      Navigator.of(context).pushNamed('/profile');
                    },
                  ),
                ],
              ),
              
              // Premium Banner (if not premium)
              if (!authService.isPremium)
                SliverToBoxAdapter(
                  child: PremiumBanner(
                    onUpgrade: () {
                      Navigator.of(context).pushNamed('/payment');
                    },
                  ),
                ),
              
              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SearchBarWidget(
                    onSearch: (query) {
                      productService.searchProducts(query);
                    },
                  ),
                ),
              ),
              
              // Category Filter
              SliverToBoxAdapter(
                child: CategoryFilter(
                  onCategorySelected: (category) {
                    productService.filterByCategory(category);
                  },
                ),
              ),
              
              // Tab Bar
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    tabs: [
                      Tab(text: localization.translate('all')),
                      Tab(text: localization.translate('recent_products')),
                      Tab(text: localization.translate('trending_products')),
                      Tab(text: localization.translate('nearby_products')),
                    ],
                  ),
                ),
              ),
              
              // Products Grid
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // All Products
                      _buildProductsGrid(productService.products, authService),
                      
                      // Recent Products
                      FutureBuilder<List<ProductModel>>(
                        future: productService.getRecentProducts(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return _buildProductsGrid(snapshot.data!, authService);
                          }
                          return const Center(child: CircularProgressIndicator());
                        },
                      ),
                      
                      // Trending Products
                      FutureBuilder<List<ProductModel>>(
                        future: productService.getTrendingProducts(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return _buildProductsGrid(snapshot.data!, authService);
                          }
                          return const Center(child: CircularProgressIndicator());
                        },
                      ),
                      
                      // Nearby Products
                      FutureBuilder<List<ProductModel>>(
                        future: locationService.selectedLocation != null
                            ? productService.getNearbyProducts(
                                locationService.selectedLocation!, 50)
                            : Future.value(<ProductModel>[]),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return _buildProductsGrid(snapshot.data!, authService);
                          }
                          return const Center(child: CircularProgressIndicator());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      
      // Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: AppLocalizations.of(context).home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search),
            label: AppLocalizations.of(context).search,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.add_circle),
            label: AppLocalizations.of(context).addProduct,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.favorite),
            label: AppLocalizations.of(context).translate('favorites'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: AppLocalizations.of(context).profile,
          ),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              // Already on home
              break;
            case 1:
              // Navigate to search
              break;
            case 2:
              // Navigate to add product
              Navigator.of(context).pushNamed('/product-upload');
              break;
            case 3:
              // Navigate to favorites
              break;
            case 4:
              // Navigate to profile
              Navigator.of(context).pushNamed('/profile');
              break;
          }
        },
      ),
      
      // Floating Action Button for Quick Upload
      floatingActionButton: Consumer<AuthService>(
        builder: (context, authService, child) {
          if (authService.canUploadProducts) {
            return FloatingActionButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/product-upload');
              },
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            );
          }
          return FloatingActionButton(
            onPressed: () {
              _showUpgradeDialog(context);
            },
            backgroundColor: AppColors.accent,
            child: const Icon(Icons.upgrade, color: Colors.white),
          );
        },
      ),
    );
  }

  Widget _buildProductsGrid(List<ProductModel> products, AuthService authService) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noData,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          product: product,
          showSellerLocation: authService.isPremium,
          onTap: () {
            Navigator.of(context).pushNamed(
              '/product-details',
              arguments: product,
            );
          },
          onFavorite: () {
            // Add to favorites
          },
        );
      },
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).premiumRequired),
        content: Text(AppLocalizations.of(context).upgradeToView),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/payment');
            },
            child: Text(AppLocalizations.of(context).upgradeNow),
          ),
        ],
      ),
    );
  }
}